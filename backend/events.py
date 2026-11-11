"""Bounded, event-driven state subscriptions over the existing local socket."""
from __future__ import annotations

import asyncio
import hashlib
import json
from typing import Any, Callable

from .errors import OmaTubeError

MAX_REQUEST = 64 * 1024
MAX_RESPONSE = 8 * 1024 * 1024


class StateEvents:
    def __init__(self, snapshot: Callable[[dict, dict], dict], interval: float = 0.25) -> None:
        self.snapshot = snapshot
        self.interval = interval
        self.clients: dict[asyncio.Task, asyncio.Event] = {}
        self.closed = False
        self.was_used = False
        self.subscriptions: dict[asyncio.Task, dict] = {}

    @property
    def retained_ids(self) -> tuple[str, ...]:
        return tuple(sorted({operation_id for options in self.subscriptions.values()
                             for operation_id in options["retainedOperationIds"]}))

    def notify(self) -> None:
        for changed in self.clients.values():
            changed.set()

    @staticmethod
    def options(request: dict) -> dict:
        if request.get("command") != "subscribe" or type(request.get("details", False)) is not bool:
            raise OmaTubeError("invalid_request", "Некорректная подписка")
        ids = request.get("retainedOperationIds", [])
        if not isinstance(ids, list) or any(not isinstance(value, str) for value in ids):
            raise OmaTubeError("invalid_request", "Некорректные operationId")
        if type(request.get("full", False)) is not bool:
            raise OmaTubeError("invalid_request", "Некорректная подписка")
        return {"details": request.get("details", False), "retainedOperationIds": ids[:8],
                "full": request.get("full", False)}

    async def serve(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, request: dict) -> None:
        options = self.options(request)
        if self.closed or len(self.clients) >= 8:
            raise OmaTubeError("provider_error", "Слишком много подписок")
        changed = asyncio.Event()
        changed.set()
        task = asyncio.current_task()
        self.clients[task] = changed
        self.subscriptions[task] = options
        self.was_used = True
        known: dict[str, Any] = {}
        previous: dict[str, bytes] = {}

        async def receive() -> None:
            while True:
                try:
                    line = await reader.readline()
                    if not line:
                        return
                    if len(line) > MAX_REQUEST:
                        raise ValueError("Request too large")
                    update = json.loads(line)
                    if not isinstance(update, dict):
                        raise ValueError("Object expected")
                    update = self.options(update)
                    update["full"] = options.get("full", False) or update["full"]
                    options.update(update)
                    changed.set()
                except (ValueError, OmaTubeError) as error:
                    raise OmaTubeError("invalid_request", "Некорректная подписка") from error

        receiver = asyncio.create_task(receive())
        waiter = None
        last_sent = 0.0
        try:
            while True:
                waiter = asyncio.create_task(changed.wait())
                done, _ = await asyncio.wait((waiter, receiver), return_when=asyncio.FIRST_COMPLETED)
                if receiver in done:
                    receiver.result()
                    return
                delay = self.interval - (asyncio.get_running_loop().time() - last_sent)
                if delay > 0:
                    await asyncio.sleep(delay)
                changed.clear()
                if options.pop("full", False):
                    known.clear()
                    previous.clear()
                state = self.snapshot(options, known)
                delta = {}
                reset = not previous
                for key, value in state.items():
                    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
                    digest = hashlib.sha256(encoded).digest()
                    del encoded
                    if previous.get(key) != digest:
                        delta[key] = value
                        previous[key] = digest
                known["backendSessionId"] = state["backendSessionId"]
                for field, revision in (("queue", "queueRevision"), ("views", "catalogRevision"),
                                        ("savedIds", "collectionRevision")):
                    if field in state:
                        known[revision] = state[revision]
                if not delta:
                    del state, delta
                    continue
                payload = json.dumps({"ok": True, "event": "state", "reset": reset, "result": delta},
                                     ensure_ascii=False, separators=(",", ":")).encode() + b"\n"
                if len(payload) > MAX_RESPONSE:
                    raise OmaTubeError("provider_error", "Ответ слишком велик")
                writer.write(payload)
                await asyncio.wait_for(writer.drain(), 5)
                # Don't retain an encoded copy of the last large catalog page while idle.
                del payload, state, delta
                last_sent = asyncio.get_running_loop().time()
        finally:
            self.clients.pop(task, None)
            self.subscriptions.pop(task, None)
            self.notify()
            receiver.cancel()
            if waiter is not None:
                waiter.cancel()
            await asyncio.gather(receiver, *([waiter] if waiter is not None else []), return_exceptions=True)

    async def stop(self) -> None:
        self.closed = True
        tasks = tuple(self.clients)
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
