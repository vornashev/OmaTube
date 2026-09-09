from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Awaitable, Callable

from .errors import OmaTubeError
from .resolver import ResolvedAudio

MAX_RESPONSE = 1024 * 1024
EventCallback = Callable[[dict[str, Any]], Awaitable[None]]
LOGGER = logging.getLogger(__name__)


class MpvController:
    def __init__(
        self,
        socket_path: Path,
        on_event: EventCallback,
        proxy: str | None = None,
    ) -> None:
        self.socket_path = socket_path
        self.on_event = on_event
        self.proxy = proxy
        self.process: asyncio.subprocess.Process | None = None
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.reader_task: asyncio.Task[None] | None = None
        self.event_task: asyncio.Task[None] | None = None
        self.event_queue: asyncio.Queue[dict[str, Any]] | None = None
        self.pending: dict[
            int,
            tuple[asyncio.StreamReader, asyncio.Future[Any]],
        ] = {}
        self.request_id = 0
        self.lifecycle_lock = asyncio.Lock()
        self._unhealthy_reader: asyncio.StreamReader | None = None
        self._closing_queues: set[asyncio.Queue[dict[str, Any]]] = set()

    def _healthy(self) -> bool:
        return bool(
            self.process
            and self.process.returncode is None
            and self.reader
            and self.reader is not self._unhealthy_reader
            and self.writer
            and not self.writer.is_closing()
            and self.reader_task
            and not self.reader_task.done()
            and self.event_task
            and not self.event_task.done()
            and self.event_queue
        )

    def _fail_pending(
        self,
        reader: asyncio.StreamReader,
        error: OmaTubeError,
    ) -> None:
        for request_id, (pending_reader, future) in list(self.pending.items()):
            if pending_reader is not reader:
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

    async def _dispose_process(
        self,
        process: asyncio.subprocess.Process | None,
        writer: asyncio.StreamWriter | None,
    ) -> None:
        if writer:
            writer.close()
            try:
                await writer.wait_closed()
            except (ConnectionError, OSError):
                pass
        if process:
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

    async def _stop_locked(self) -> None:
        process = self.process
        reader = self.reader
        writer = self.writer
        reader_task = self.reader_task
        event_task = self.event_task
        queue = self.event_queue
        if queue:
            self._closing_queues.add(queue)
        self.process = None
        self.reader = None
        self.writer = None
        self.reader_task = None
        self.event_task = None
        self.event_queue = None
        self._unhealthy_reader = None

        current_task = asyncio.current_task()
        tasks = [
            task
            for task in (reader_task, event_task)
            if task and task is not current_task
        ]
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        if reader:
            self._fail_pending(
                reader,
                OmaTubeError("playback_error", "Связь с mpv потеряна"),
            )
        await self._dispose_process(process, writer)
        if queue:
            self._closing_queues.discard(queue)
        self.socket_path.unlink(missing_ok=True)

    async def _start_locked(self) -> None:
        if self._healthy():
            return
        if (
            self.process
            or self.writer
            or self.reader_task
            or self.event_task
            or self.event_queue
        ):
            await self._stop_locked()
        self.socket_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.socket_path.unlink(missing_ok=True)
        argv = [
            "mpv",
            "--idle=yes",
            "--no-config",
            "--no-video",
            "--audio-display=no",
            "--no-terminal",
            "--load-scripts=no",
            "--force-window=no",
            "--audio-client-name=OmaTube",
            f"--input-ipc-server={self.socket_path}",
        ]
        if self.proxy:
            argv.append(f"--http-proxy={self.proxy}")
        try:
            process = await asyncio.create_subprocess_exec(
                *argv,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
        except FileNotFoundError as exc:
            raise OmaTubeError("dependency_missing", "Не найден mpv") from exc

        reader: asyncio.StreamReader | None = None
        writer: asyncio.StreamWriter | None = None
        try:
            for _ in range(100):
                if process.returncode is not None:
                    raise OmaTubeError(
                        "playback_error",
                        "mpv завершился при запуске",
                    )
                try:
                    reader, writer = await asyncio.open_unix_connection(
                        self.socket_path
                    )
                    break
                except (FileNotFoundError, ConnectionRefusedError):
                    await asyncio.sleep(0.05)
            else:
                raise OmaTubeError(
                    "playback_error",
                    "mpv не создал управляющий сокет",
                )
            self.socket_path.chmod(0o600)
            queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
            self.process = process
            self.reader = reader
            self.writer = writer
            self.event_queue = queue
            self._unhealthy_reader = None
            self.reader_task = asyncio.create_task(
                self._read_loop(reader, queue)
            )
            self.event_task = asyncio.create_task(self._event_loop(queue))
            for property_name in (
                "pause",
                "time-pos",
                "duration",
                "seekable",
                "idle-active",
                "volume",
                "mute",
            ):
                await self._command_connected(
                    ["observe_property", 0, property_name]
                )
        except BaseException:
            if self.process is process:
                await self._stop_locked()
            else:
                await self._dispose_process(process, writer)
                self.socket_path.unlink(missing_ok=True)
            raise

    async def start(self) -> None:
        async with self.lifecycle_lock:
            await self._start_locked()

    async def _read_loop(
        self,
        reader: asyncio.StreamReader,
        event_queue: asyncio.Queue[dict[str, Any]],
    ) -> None:
        try:
            while line := await reader.readline():
                if len(line) > MAX_RESPONSE:
                    raise OmaTubeError(
                        "playback_error",
                        "Ответ mpv слишком велик",
                    )
                try:
                    payload = json.loads(line)
                except json.JSONDecodeError:
                    continue
                request_id = payload.get("request_id")
                pending = self.pending.get(request_id)
                if pending and pending[0] is reader:
                    self.pending.pop(request_id, None)
                    future = pending[1]
                    if future.done():
                        continue
                    if payload.get("error") == "success":
                        future.set_result(payload.get("data"))
                    else:
                        future.set_exception(OmaTubeError(
                            "playback_error",
                            f"mpv отклонил команду: {payload.get('error', 'unknown error')}",
                        ))
                elif payload.get("event"):
                    event_queue.put_nowait(payload)
        finally:
            if self.reader is reader:
                self._unhealthy_reader = reader
            self._fail_pending(
                reader,
                OmaTubeError("playback_error", "Связь с mpv потеряна"),
            )
            if event_queue not in self._closing_queues:
                event_queue.put_nowait({"event": "omatube-disconnected"})

    async def _event_loop(
        self,
        queue: asyncio.Queue[dict[str, Any]],
    ) -> None:
        while True:
            event = await queue.get()
            try:
                if queue is not self.event_queue:
                    return
                await self.on_event(event)
            except asyncio.CancelledError:
                raise
            except Exception:
                LOGGER.exception("Unhandled mpv event callback")
            finally:
                queue.task_done()
            if queue is not self.event_queue:
                return

    async def _command_connected(self, command: list[Any]) -> Any:
        assert self.reader and self.writer
        reader = self.reader
        writer = self.writer
        self.request_id += 1
        request_id = self.request_id
        future = asyncio.get_running_loop().create_future()
        self.pending[request_id] = (reader, future)
        payload = json.dumps(
            {"command": command, "request_id": request_id},
            separators=(",", ":"),
        )
        try:
            writer.write((payload + "\n").encode())
            await writer.drain()
            return await asyncio.wait_for(future, 5)
        except TimeoutError as exc:
            if self.reader is reader:
                self._unhealthy_reader = reader
            writer.close()
            raise OmaTubeError(
                "playback_error",
                "mpv не ответил на команду",
            ) from exc
        except (ConnectionError, OSError, RuntimeError) as exc:
            if self.reader is reader:
                self._unhealthy_reader = reader
            raise OmaTubeError(
                "playback_error",
                "Не удалось отправить команду mpv",
            ) from exc
        finally:
            pending = self.pending.get(request_id)
            if pending and pending[1] is future:
                self.pending.pop(request_id, None)
            if not future.done():
                future.cancel()

    async def command(self, command: list[Any]) -> Any:
        async with self.lifecycle_lock:
            await self._start_locked()
            return await self._command_connected(command)

    async def load(self, audio: ResolvedAudio, start: float = 0.0) -> None:
        headers = [f"{key}: {value}" for key, value in audio.headers.items()]
        await self.command(["set_property", "http-header-fields", headers])
        command: list[Any] = ["loadfile", audio.url, "replace"]
        if start > 0:
            command.extend([-1, f"start={start}"])
        await self.command(command)
        await self.command(["set_property", "pause", False])

    async def pause(self, paused: bool) -> None:
        await self.command(["set_property", "pause", paused])

    async def seek(self, seconds: float) -> None:
        await self.command(["seek", max(0.0, seconds), "absolute", "exact"])

    async def set_volume(self, value: float) -> None:
        await self.command([
            "set_property",
            "volume",
            max(0.0, min(100.0, value)),
        ])

    async def set_mute(self, value: bool) -> None:
        await self.command(["set_property", "mute", value])

    async def stop_playback(self) -> None:
        if self.writer:
            await self.command(["stop"])

    async def stop(self) -> None:
        async with self.lifecycle_lock:
            await self._stop_locked()
