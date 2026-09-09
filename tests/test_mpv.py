import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, call, patch

from backend.errors import OmaTubeError
from backend.mpv import MpvController


class FakeProcess:
    def __init__(self, returncode=None):
        self.returncode = returncode
        self.terminated = 0
        self.killed = 0

    def terminate(self):
        self.terminated += 1
        self.returncode = 0

    def kill(self):
        self.killed += 1
        self.returncode = -9

    async def wait(self):
        return self.returncode


class FakeWriter:
    def __init__(self, reader=None, respond=False):
        self.reader = reader
        self.respond = respond
        self.data = []
        self.written = asyncio.Event()
        self.closing = False

    def write(self, data):
        self.data.append(data)
        self.written.set()
        if self.respond:
            request_id = json.loads(data)["request_id"]
            self.reader.feed_data(json.dumps({
                "request_id": request_id,
                "error": "success",
                "data": "ok",
            }).encode() + b"\n")

    async def drain(self):
        pass

    def is_closing(self):
        return self.closing

    def close(self):
        self.closing = True

    async def wait_closed(self):
        pass


class MpvControllerTests(unittest.IsolatedAsyncioTestCase):
    async def test_event_callback_can_issue_command_without_blocking_responses(self):
        callback_done = asyncio.Event()
        controller = None

        async def on_event(_event):
            await controller.command(["stop"])
            callback_done.set()

        with tempfile.TemporaryDirectory() as directory:
            controller = MpvController(Path(directory) / "mpv.sock", on_event)
            controller.process = FakeProcess()
            controller.reader = asyncio.StreamReader()
            controller.writer = FakeWriter(controller.reader, respond=True)
            controller.event_queue = asyncio.Queue()
            controller.reader_task = asyncio.create_task(controller._read_loop(
                controller.reader,
                controller.event_queue,
            ))
            controller.event_task = asyncio.create_task(controller._event_loop(
                controller.event_queue,
            ))

            controller.reader.feed_data(b'{"event":"end-file","reason":"eof"}\n')
            await asyncio.wait_for(callback_done.wait(), 0.5)
            await controller.stop()

    async def test_late_response_for_cancelled_request_does_not_kill_reader(self):
        async def on_event(_event):
            pass

        with tempfile.TemporaryDirectory() as directory:
            controller = MpvController(Path(directory) / "mpv.sock", on_event)
            reader = asyncio.StreamReader()
            queue = asyncio.Queue()
            cancelled = asyncio.get_running_loop().create_future()
            cancelled.cancel()
            next_response = asyncio.get_running_loop().create_future()
            controller.pending = {
                1: (reader, cancelled),
                2: (reader, next_response),
            }
            task = asyncio.create_task(controller._read_loop(reader, queue))

            reader.feed_data(b'{"request_id":1,"error":"success"}\n')
            reader.feed_data(b'{"request_id":2,"error":"success","data":"ok"}\n')
            self.assertEqual(await asyncio.wait_for(next_response, 0.5), "ok")
            reader.feed_eof()
            await asyncio.wait_for(task, 0.5)

    async def test_command_timeout_marks_session_unhealthy_and_clears_pending(self):
        async def on_event(_event):
            pass

        with tempfile.TemporaryDirectory() as directory:
            controller = MpvController(Path(directory) / "mpv.sock", on_event)
            controller._start_locked = AsyncMock()
            controller.reader = asyncio.StreamReader()
            controller.writer = FakeWriter()
            with patch("backend.mpv.asyncio.wait_for", AsyncMock(side_effect=TimeoutError)):
                with self.assertRaises(OmaTubeError) as caught:
                    await controller.command(["get_property", "idle-active"])

            self.assertEqual(caught.exception.code, "playback_error")
            self.assertEqual(controller.pending, {})
            self.assertTrue(controller.writer.is_closing())
            self.assertIs(controller._unhealthy_reader, controller.reader)

    async def test_simultaneous_cold_commands_create_one_session(self):
        async def on_event(_event):
            pass

        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "mpv.sock"
            controller = MpvController(socket_path, on_event)
            process = FakeProcess()
            reader = asyncio.StreamReader()
            writer = FakeWriter(reader, respond=True)

            async def connect(_path):
                socket_path.touch()
                return reader, writer

            with patch(
                "backend.mpv.asyncio.create_subprocess_exec",
                AsyncMock(return_value=process),
            ) as spawn, patch(
                "backend.mpv.asyncio.open_unix_connection",
                AsyncMock(side_effect=connect),
            ):
                results = await asyncio.gather(
                    controller.command(["get_property", "pause"]),
                    controller.command(["get_property", "volume"]),
                )

            self.assertEqual(results, ["ok", "ok"])
            self.assertEqual(spawn.await_count, 1)
            await controller.stop()

    async def test_video_loader_brackets_window_preparation(self):
        async def on_event(_event):
            pass

        with tempfile.TemporaryDirectory() as directory:
            controller = MpvController(Path(directory) / "mpv.sock", on_event)
            stream = type("Stream", (), {"url": "https://stream.invalid/combined"})()
            controller.loaded = type("Media", (), {"audio": stream, "video": stream})()
            controller.command = AsyncMock()
            controller.set_video_loading = AsyncMock()
            controller._place_video = AsyncMock()

            await controller.set_video_mode("tile")

        self.assertEqual(
            controller.set_video_loading.await_args_list,
            [call(True), call(False)],
        )
        controller._place_video.assert_awaited_once_with("tile")

    async def test_unexpected_eof_emits_one_disconnect_but_clean_stop_emits_none(self):
        events = []
        disconnected = asyncio.Event()

        async def on_event(event):
            events.append(event)
            if event.get("event") == "omatube-disconnected":
                disconnected.set()

        with tempfile.TemporaryDirectory() as directory:
            controller = MpvController(Path(directory) / "mpv.sock", on_event)
            controller.process = FakeProcess()
            controller.reader = asyncio.StreamReader()
            controller.writer = FakeWriter()
            controller.event_queue = asyncio.Queue()
            controller.reader_task = asyncio.create_task(controller._read_loop(
                controller.reader,
                controller.event_queue,
            ))
            controller.event_task = asyncio.create_task(controller._event_loop(
                controller.event_queue,
            ))
            controller.reader.feed_eof()
            await asyncio.wait_for(disconnected.wait(), 0.5)
            await asyncio.sleep(0)
            self.assertEqual(
                [event["event"] for event in events],
                ["omatube-disconnected"],
            )
            await controller.stop()
            self.assertEqual(len(events), 1)

            clean_events = []
            clean = MpvController(
                Path(directory) / "clean.sock",
                lambda event: self._append_event(clean_events, event),
            )
            clean.process = FakeProcess()
            clean.reader = asyncio.StreamReader()
            clean.writer = FakeWriter()
            clean.event_queue = asyncio.Queue()
            clean.reader_task = asyncio.create_task(clean._read_loop(
                clean.reader,
                clean.event_queue,
            ))
            clean.event_task = asyncio.create_task(clean._event_loop(
                clean.event_queue,
            ))
            await clean.stop()
            self.assertEqual(clean_events, [])

    async def test_old_session_disconnect_is_not_delivered_to_new_session(self):
        events = []

        async def on_event(event):
            events.append(event)

        with tempfile.TemporaryDirectory() as directory:
            controller = MpvController(Path(directory) / "mpv.sock", on_event)
            old_reader = asyncio.StreamReader()
            old_queue = asyncio.Queue()
            controller.event_queue = asyncio.Queue()
            old_reader_task = asyncio.create_task(controller._read_loop(
                old_reader,
                old_queue,
            ))
            old_event_task = asyncio.create_task(controller._event_loop(old_queue))
            old_reader.feed_eof()
            await asyncio.wait_for(old_reader_task, 0.5)
            await asyncio.wait_for(old_event_task, 0.5)
            self.assertEqual(events, [])

    async def test_startup_failure_leaves_no_partial_session(self):
        async def on_event(_event):
            pass

        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "mpv.sock"
            controller = MpvController(socket_path, on_event)
            process = FakeProcess(returncode=1)
            with patch(
                "backend.mpv.asyncio.create_subprocess_exec",
                AsyncMock(return_value=process),
            ):
                with self.assertRaises(OmaTubeError) as caught:
                    await controller.start()

            self.assertEqual(caught.exception.code, "playback_error")
            self.assertIsNone(controller.process)
            self.assertIsNone(controller.reader)
            self.assertIsNone(controller.writer)
            self.assertIsNone(controller.reader_task)
            self.assertIsNone(controller.event_task)
            self.assertFalse(socket_path.exists())

    @staticmethod
    async def _append_event(target, event):
        target.append(event)


if __name__ == "__main__":
    unittest.main()
