import asyncio
import signal
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

from backend.resolver import AudioResolver


class ResolverTests(unittest.IsolatedAsyncioTestCase):
    async def test_cancelling_resolve_kills_extractor_process_group(self):
        async def wait_forever():
            await asyncio.Future()

        process = SimpleNamespace(
            pid=4321,
            returncode=None,
            communicate=wait_forever,
            wait=AsyncMock(return_value=0),
        )
        resolver = AudioResolver("python")
        with patch("backend.resolver.asyncio.create_subprocess_exec", AsyncMock(return_value=process)) as spawn, \
             patch("backend.resolver.os.killpg") as killpg:
            task = asyncio.create_task(resolver.resolve_audio("AAAAAA1"))
            await asyncio.sleep(0)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task

        self.assertTrue(spawn.await_args.kwargs["start_new_session"])
        killpg.assert_called_once_with(4321, signal.SIGKILL)
        process.wait.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
