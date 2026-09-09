from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
from typing import Any

from .errors import OmaTubeError

MAX_LINE = 8 * 1024 * 1024
RETRY_DELAYS = (0.6, 1.2, 2.4)



class CatalogBridge:
    def __init__(self, worker: Path, node: str = "node", proxy: str | None = None) -> None:
        self.worker = worker
        self.node = node
        self.proxy = proxy
        self.process: asyncio.subprocess.Process | None = None
        self.reader_task: asyncio.Task[None] | None = None
        self.pending: dict[
            int,
            tuple[asyncio.subprocess.Process, asyncio.Future[dict[str, Any]]],
        ] = {}
        self.serial = 0
        self.write_lock = asyncio.Lock()
        self.lifecycle_lock = asyncio.Lock()
        self._unhealthy_process: asyncio.subprocess.Process | None = None

    def _healthy(self) -> bool:
        return bool(
            self.process
            and self.process.returncode is None
            and self.process.stdin
            and not self.process.stdin.is_closing()
            and self.process.stdout
            and self.reader_task
            and not self.reader_task.done()
            and self._unhealthy_process is not self.process
        )

    def _fail_pending(self, process: asyncio.subprocess.Process, error: OmaTubeError) -> None:
        for request_id, (pending_process, future) in list(self.pending.items()):
            if pending_process is not process:
                continue
            self.pending.pop(request_id, None)
            if not future.done():
                future.set_exception(error)

    @staticmethod
    def _terminate(process: asyncio.subprocess.Process) -> None:
        if process.returncode is not None:
            return
        try:
            process.terminate()
        except ProcessLookupError:
            pass

    async def _stop_locked(self) -> None:
        process = self.process
        reader_task = self.reader_task
        self.process = None
        self.reader_task = None
        self._unhealthy_process = None
        if process:
            self._fail_pending(
                process,
                OmaTubeError("provider_error", "Связь с процессом каталога потеряна"),
            )
            if process.stdin:
                process.stdin.close()
            self._terminate(process)
            if process.returncode is None:
                try:
                    await asyncio.wait_for(process.wait(), 3)
                except TimeoutError:
                    try:
                        process.kill()
                    except ProcessLookupError:
                        pass
                    await process.wait()
        current_task = asyncio.current_task()
        if reader_task and reader_task is not current_task:
            reader_task.cancel()
            await asyncio.gather(reader_task, return_exceptions=True)

    async def _start_locked(self) -> None:
        if self._healthy():
            return
        if self.process or self.reader_task:
            await self._stop_locked()
        env = None
        if self.proxy:
            env = os.environ.copy()
            env.update({
                "HTTP_PROXY": self.proxy,
                "HTTPS_PROXY": self.proxy,
                "NODE_USE_ENV_PROXY": "1",
                "NO_PROXY": ",".join(filter(None, [env.get("NO_PROXY"), "localhost,127.0.0.1,::1"])),
            })
        try:
            process = await asyncio.create_subprocess_exec(
                self.node,
                str(self.worker),
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=None,
                env=env,
                limit=MAX_LINE + 1,
            )
        except FileNotFoundError as exc:
            raise OmaTubeError("dependency_missing", "Не найден Node.js") from exc
        self.process = process
        self._unhealthy_process = None
        self.reader_task = asyncio.create_task(self._reader(process))

    async def start(self) -> None:
        async with self.lifecycle_lock:
            await self._start_locked()

    @staticmethod
    def _response_error() -> OmaTubeError:
        return OmaTubeError("provider_error", "Некорректный ответ процесса каталога")

    async def _reader(self, process: asyncio.subprocess.Process) -> None:
        assert process.stdout
        terminal_error = OmaTubeError(
            "provider_error",
            "Связь с процессом каталога потеряна",
        )
        malformed = False
        try:
            while True:
                try:
                    line = await process.stdout.readline()
                except (ValueError, asyncio.LimitOverrunError):
                    terminal_error = self._response_error()
                    malformed = True
                    break
                if not line:
                    break
                if len(line) > MAX_LINE:
                    terminal_error = self._response_error()
                    malformed = True
                    break
                try:
                    response = json.loads(line)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    terminal_error = self._response_error()
                    malformed = True
                    break
                if (
                    not isinstance(response, dict)
                    or type(response.get("id")) is not int
                    or type(response.get("ok")) is not bool
                ):
                    terminal_error = self._response_error()
                    malformed = True
                    break
                request_id = response["id"]
                result = response.get("result")
                error = response.get("error")
                if response["ok"]:
                    if not isinstance(result, dict):
                        terminal_error = self._response_error()
                        malformed = True
                        break
                elif (
                    not isinstance(error, dict)
                    or not isinstance(error.get("code"), str)
                    or not isinstance(error.get("message"), str)
                ):
                    terminal_error = self._response_error()
                    malformed = True
                    break
                pending = self.pending.get(request_id)
                if not pending or pending[0] is not process:
                    continue
                self.pending.pop(request_id, None)
                future = pending[1]
                if future.done():
                    continue
                if response["ok"]:
                    future.set_result(result)
                else:
                    future.set_exception(OmaTubeError(error["code"], error["message"]))
        finally:
            if self.process is process:
                self._unhealthy_process = process
            if malformed:
                self._terminate(process)
            self._fail_pending(process, terminal_error)

    async def _request_once(
        self,
        method: str,
        params: dict[str, Any],
        timeout: float,
    ) -> dict[str, Any]:
        request_id: int | None = None
        future: asyncio.Future[dict[str, Any]] | None = None
        process: asyncio.subprocess.Process | None = None
        try:
            async with self.lifecycle_lock:
                await self._start_locked()
                assert self.process and self.process.stdin
                process = self.process
                async with self.write_lock:
                    self.serial += 1
                    request_id = self.serial
                    payload = (
                        json.dumps(
                            {"id": request_id, "method": method, "params": params},
                            ensure_ascii=False,
                            separators=(",", ":"),
                        )
                        + "\n"
                    ).encode("utf-8")
                    if len(payload) > 64 * 1024:
                        raise OmaTubeError("invalid_request", "Запрос каталога слишком велик")
                    future = asyncio.get_running_loop().create_future()
                    self.pending[request_id] = (process, future)
                    try:
                        process.stdin.write(payload)
                        await process.stdin.drain()
                    except (ConnectionError, OSError, RuntimeError) as exc:
                        if self.process is process:
                            self._unhealthy_process = process
                        process.stdin.close()
                        self._terminate(process)
                        raise OmaTubeError(
                            "provider_error",
                            "Связь с процессом каталога потеряна",
                        ) from exc
            assert future
            return await asyncio.wait_for(future, timeout)
        finally:
            if request_id is not None and future is not None:
                pending = self.pending.get(request_id)
                if pending and pending[1] is future:
                    self.pending.pop(request_id, None)
                if not future.done():
                    future.cancel()

    async def request(
        self,
        method: str,
        params: dict[str, Any],
        timeout: float = 45,
    ) -> dict[str, Any]:
        retryable = method in {"search", "suggestions", "ping"}
        try:
            async with asyncio.timeout(timeout):
                for attempt in range(len(RETRY_DELAYS) + 1):
                    try:
                        return await self._request_once(method, params, timeout)
                    except OmaTubeError as error:
                        if (
                            not retryable
                            or error.code != "network_error"
                            or attempt >= len(RETRY_DELAYS)
                        ):
                            raise
                        await asyncio.sleep(RETRY_DELAYS[attempt])
        except TimeoutError as exc:
            raise OmaTubeError(
                "network_error",
                "Каталог не ответил вовремя",
            ) from exc
        raise AssertionError("unreachable")

    async def stop(self) -> None:
        async with self.lifecycle_lock:
            await self._stop_locked()
