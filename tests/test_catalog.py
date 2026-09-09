import asyncio
import json
from pathlib import Path
import unittest
from unittest.mock import AsyncMock, patch

from backend.catalog import MAX_LINE, CatalogBridge
from backend.errors import OmaTubeError


class FakeWriter:
    def __init__(self, drain_error: Exception | None = None) -> None:
        self.data: list[bytes] = []
        self.written = asyncio.Event()
        self.closing = False
        self.drain_error = drain_error

    def write(self, data: bytes) -> None:
        self.data.append(data)
        self.written.set()

    async def drain(self) -> None:
        if self.drain_error:
            raise self.drain_error

    def is_closing(self) -> bool:
        return self.closing

    def close(self) -> None:
        self.closing = True

    async def wait_for_count(self, count: int) -> None:
        while len(self.data) < count:
            self.written.clear()
            if len(self.data) >= count:
                break
            await asyncio.wait_for(self.written.wait(), 0.5)


class FakeProcess:
    def __init__(self, drain_error: Exception | None = None) -> None:
        self.stdin = FakeWriter(drain_error)
        self.stdout = asyncio.StreamReader(limit=MAX_LINE + 1)
        self.returncode: int | None = None

    def terminate(self) -> None:
        self.returncode = -15
        self.stdout.feed_eof()

    def kill(self) -> None:
        self.returncode = -9
        self.stdout.feed_eof()

    async def wait(self) -> int:
        return self.returncode or 0


def request_id(process: FakeProcess, index: int) -> int:
    return json.loads(process.stdin.data[index])["id"]


def feed_success(process: FakeProcess, request: int, result: dict) -> None:
    process.stdout.feed_data(
        json.dumps({"id": request, "ok": True, "result": result}).encode() + b"\n"
    )


def feed_error(process: FakeProcess, request: int, code: str, message: str) -> None:
    process.stdout.feed_data(
        json.dumps(
            {"id": request, "ok": False, "error": {"code": code, "message": message}}
        ).encode()
        + b"\n"
    )


class CatalogBridgeTests(unittest.IsolatedAsyncioTestCase):
    async def test_late_cancelled_response_and_large_response_keep_reader_alive(self):
        process = FakeProcess()
        bridge = CatalogBridge(Path("worker.mjs"))
        with patch(
            "backend.catalog.asyncio.create_subprocess_exec",
            new=AsyncMock(return_value=process),
        ):
            cancelled = asyncio.create_task(bridge.request("next", {}, timeout=1))
            await process.stdin.wait_for_count(1)
            cancelled_id = request_id(process, 0)
            cancelled.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await cancelled

            current = asyncio.create_task(bridge.request("next", {}, timeout=1))
            await process.stdin.wait_for_count(2)
            current_id = request_id(process, 1)
            feed_success(process, cancelled_id, {"items": ["late"]})
            large_item = "x" * (128 * 1024)
            feed_success(process, current_id, {"items": [large_item]})

            self.assertEqual(
                await asyncio.wait_for(current, 0.5),
                {"items": [large_item]},
            )
            self.assertFalse(bridge.reader_task.done())
            await bridge.stop()

    async def test_protocol_violations_fail_pending_and_replace_worker(self):
        invalid_responses = (
            b"not-json\n",
            b'{"id":1,"ok":true,"result":[]}\n',
            b"x" * (MAX_LINE + 1) + b"\n",
        )
        for invalid_response in invalid_responses:
            with self.subTest(response_size=len(invalid_response)):
                damaged = FakeProcess()
                replacement = FakeProcess()
                bridge = CatalogBridge(Path("worker.mjs"))
                with patch(
                    "backend.catalog.asyncio.create_subprocess_exec",
                    new=AsyncMock(side_effect=[damaged, replacement]),
                ):
                    failed = asyncio.create_task(bridge.request("next", {}, timeout=1))
                    await damaged.stdin.wait_for_count(1)
                    damaged.stdout.feed_data(invalid_response)
                    with self.assertRaises(OmaTubeError) as caught:
                        await asyncio.wait_for(failed, 0.5)
                    self.assertEqual(caught.exception.code, "provider_error")
                    self.assertEqual(
                        caught.exception.message,
                        "Некорректный ответ процесса каталога",
                    )

                    recovered = asyncio.create_task(
                        bridge.request("next", {}, timeout=1)
                    )
                    await replacement.stdin.wait_for_count(1)
                    feed_success(
                        replacement,
                        request_id(replacement, 0),
                        {"items": ["ready"]},
                    )
                    self.assertEqual(
                        await asyncio.wait_for(recovered, 0.5),
                        {"items": ["ready"]},
                    )
                    await bridge.stop()

    async def test_eof_and_broken_pipe_replace_worker(self):
        for transport in ("eof", "broken-pipe"):
            with self.subTest(transport=transport):
                damaged = FakeProcess(
                    BrokenPipeError() if transport == "broken-pipe" else None
                )
                replacement = FakeProcess()
                bridge = CatalogBridge(Path("worker.mjs"))
                with patch(
                    "backend.catalog.asyncio.create_subprocess_exec",
                    new=AsyncMock(side_effect=[damaged, replacement]),
                ):
                    failed = asyncio.create_task(bridge.request("next", {}, timeout=1))
                    await damaged.stdin.wait_for_count(1)
                    if transport == "eof":
                        damaged.stdout.feed_eof()
                    with self.assertRaises(OmaTubeError) as caught:
                        await asyncio.wait_for(failed, 0.5)
                    self.assertEqual(caught.exception.code, "provider_error")
                    self.assertEqual(
                        caught.exception.message,
                        "Связь с процессом каталога потеряна",
                    )

                    recovered = asyncio.create_task(
                        bridge.request("next", {}, timeout=1)
                    )
                    await replacement.stdin.wait_for_count(1)
                    feed_success(
                        replacement,
                        request_id(replacement, 0),
                        {"items": ["ready"]},
                    )
                    self.assertEqual(
                        await asyncio.wait_for(recovered, 0.5),
                        {"items": ["ready"]},
                    )
                    await bridge.stop()

    async def test_simultaneous_cold_requests_share_one_worker(self):
        process = FakeProcess()
        bridge = CatalogBridge(Path("worker.mjs"))
        spawn = AsyncMock(return_value=process)
        with patch("backend.catalog.asyncio.create_subprocess_exec", new=spawn):
            first = asyncio.create_task(bridge.request("next", {"cursor": "a"}))
            second = asyncio.create_task(bridge.request("next", {"cursor": "b"}))
            await process.stdin.wait_for_count(2)
            for index, item in enumerate(("first", "second")):
                feed_success(
                    process,
                    request_id(process, index),
                    {"items": [item]},
                )
            results = await asyncio.gather(first, second)

            self.assertCountEqual(
                results,
                [{"items": ["first"]}, {"items": ["second"]}],
            )
            self.assertEqual(spawn.await_count, 1)
            await bridge.stop()

    async def test_overall_deadline_sends_only_one_provider_request(self):
        process = FakeProcess()
        bridge = CatalogBridge(Path("worker.mjs"))
        with patch(
            "backend.catalog.asyncio.create_subprocess_exec",
            new=AsyncMock(return_value=process),
        ):
            with self.assertRaises(OmaTubeError) as caught:
                await bridge.request("search", {"query": "test"}, timeout=0.02)

            self.assertEqual(caught.exception.code, "network_error")
            self.assertEqual(caught.exception.message, "Каталог не ответил вовремя")
            self.assertEqual(len(process.stdin.data), 1)
            await bridge.stop()

    async def test_only_idempotent_methods_retry_worker_network_error(self):
        process = FakeProcess()
        bridge = CatalogBridge(Path("worker.mjs"))
        with (
            patch(
                "backend.catalog.asyncio.create_subprocess_exec",
                new=AsyncMock(return_value=process),
            ),
            patch("backend.catalog.RETRY_DELAYS", (0,)),
        ):
            search = asyncio.create_task(
                bridge.request("search", {"query": "test"}, timeout=1)
            )
            await process.stdin.wait_for_count(1)
            feed_error(
                process,
                request_id(process, 0),
                "network_error",
                "temporary",
            )
            await process.stdin.wait_for_count(2)
            feed_success(
                process,
                request_id(process, 1),
                {"items": ["ready"]},
            )
            self.assertEqual(await search, {"items": ["ready"]})

            continuation = asyncio.create_task(
                bridge.request("next", {"cursor": "cursor"}, timeout=1)
            )
            await process.stdin.wait_for_count(3)
            feed_error(
                process,
                request_id(process, 2),
                "network_error",
                "temporary",
            )
            with self.assertRaises(OmaTubeError) as caught:
                await continuation
            self.assertEqual(caught.exception.code, "network_error")
            self.assertEqual(len(process.stdin.data), 3)
            await bridge.stop()

    async def test_provider_errors_are_not_retried(self):
        process = FakeProcess()
        bridge = CatalogBridge(Path("worker.mjs"))
        with patch(
            "backend.catalog.asyncio.create_subprocess_exec",
            new=AsyncMock(return_value=process),
        ):
            request = asyncio.create_task(
                bridge.request("search", {"query": "test"}, timeout=1)
            )
            await process.stdin.wait_for_count(1)
            feed_error(
                process,
                request_id(process, 0),
                "provider_error",
                "invalid provider response",
            )
            with self.assertRaisesRegex(OmaTubeError, "invalid provider response"):
                await request
            self.assertEqual(len(process.stdin.data), 1)
            await bridge.stop()


if __name__ == "__main__":
    unittest.main()
