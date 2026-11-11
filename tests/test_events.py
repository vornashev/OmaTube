import asyncio
import json
from pathlib import Path
import tempfile
import unittest

from backend.events import StateEvents
from backend.errors import OmaTubeError


class EventTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "events.sock"
        self.state = {"backendSessionId": "one", "position": 0, "queueRevision": 1,
                      "preferences": {"language": "en"}}
        self.calls = 0
        def snapshot(options, known):
            self.calls += 1
            result = dict(self.state)
            if options["details"] and known.get("queueRevision") != self.state["queueRevision"]:
                result["queue"] = [{"entryId": "entry"}]
            return result
        self.events = StateEvents(snapshot, interval=0.01)
        self.writers = []
        async def handle(reader, writer):
            try:
                request = json.loads(await reader.readline())
                await self.events.serve(reader, writer, request)
            except OmaTubeError as error:
                writer.write(json.dumps({"ok": False, "error": error.as_dict()}).encode() + b"\n")
                await writer.drain()
            finally:
                writer.close()
                await writer.wait_closed()
        self.server = await asyncio.start_unix_server(handle, self.path)

    async def asyncTearDown(self):
        await self.events.stop()
        for writer in self.writers:
            writer.close()
            await writer.wait_closed()
        self.server.close()
        await self.server.wait_closed()
        self.tmp.cleanup()

    async def connect(self, **options):
        reader, writer = await asyncio.open_unix_connection(self.path)
        self.writers.append(writer)
        writer.write(json.dumps({"command": "subscribe", **options}).encode() + b"\n")
        await writer.drain()
        return reader, writer

    async def frame(self, reader):
        return json.loads(await asyncio.wait_for(reader.readline(), 1))

    async def test_initial_snapshot_then_silent_idle_and_position_delta(self):
        reader, _ = await self.connect()
        first = await self.frame(reader)
        self.assertTrue(first["reset"])
        self.assertEqual(first["result"], self.state)
        with self.assertRaises(TimeoutError):
            await asyncio.wait_for(reader.readline(), 0.05)
        self.assertEqual(self.calls, 1)
        self.state["position"] = 42
        for _ in range(100):
            self.events.notify()
        self.assertEqual((await self.frame(reader))["result"], {"position": 42})
        self.events.notify()
        with self.assertRaises(TimeoutError):
            await asyncio.wait_for(reader.readline(), 0.05)

    async def test_mutable_preferences_are_detected(self):
        reader, _ = await self.connect()
        await self.frame(reader)
        self.state["preferences"]["language"] = "ru"
        self.events.notify()
        self.assertEqual((await self.frame(reader))["result"], {"preferences": {"language": "ru"}})

    async def test_open_details_and_request_full_reset(self):
        reader, writer = await self.connect()
        self.assertNotIn("queue", (await self.frame(reader))["result"])
        writer.write(b'{"command":"subscribe","details":true}\n')
        await writer.drain()
        self.assertIn("queue", (await self.frame(reader))["result"])
        writer.write(b'{"command":"subscribe","details":true,"full":true}\n')
        await writer.drain()
        full = await self.frame(reader)
        self.assertTrue(full["reset"])
        self.assertIn("queue", full["result"])

    async def test_disconnect_releases_subscription(self):
        reader, writer = await self.connect()
        await self.frame(reader)
        writer.close()
        await writer.wait_closed()
        for _ in range(50):
            if not self.events.clients:
                break
            await asyncio.sleep(0.01)
        self.assertEqual(len(self.events.clients), 0)

    async def test_invalid_update_closes_stream_with_error(self):
        reader, writer = await self.connect()
        await self.frame(reader)
        writer.write(b'{"command":"subscribe","details":"yes"}\n')
        await writer.drain()
        self.assertFalse((await self.frame(reader))["ok"])
        self.assertEqual(await reader.readline(), b"")

    async def test_new_connection_receives_full_snapshot(self):
        first, writer = await self.connect()
        await self.frame(first)
        writer.close()
        await writer.wait_closed()
        self.state["position"] = 5
        reader, _ = await self.connect()
        frame = await self.frame(reader)
        self.assertTrue(frame["reset"])
        self.assertEqual(frame["result"]["position"], 5)

    async def test_retained_ids_belong_to_live_subscriptions(self):
        first, writer = await self.connect(retainedOperationIds=["a"])
        await self.frame(first)
        second, _ = await self.connect(retainedOperationIds=["b"])
        await self.frame(second)
        self.assertEqual(self.events.retained_ids, ("a", "b"))
        writer.close()
        await writer.wait_closed()
        for _ in range(50):
            if self.events.retained_ids == ("b",):
                break
            await asyncio.sleep(0.01)
        self.assertEqual(self.events.retained_ids, ("b",))

    async def test_full_refresh_is_not_lost_when_updates_are_coalesced(self):
        reader, writer = await self.connect(details=True)
        await self.frame(reader)
        writer.write(b'{"command":"subscribe","details":true,"full":true}\n'
                     b'{"command":"subscribe","details":true}\n')
        await writer.drain()
        frame = await self.frame(reader)
        self.assertTrue(frame["reset"])
        self.assertIn("queue", frame["result"])
