import asyncio
import json
from pathlib import Path
import signal
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

from backend.resolver import MediaResolver


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
        resolver = MediaResolver("python")
        with patch("backend.resolver.asyncio.create_subprocess_exec", AsyncMock(return_value=process)) as spawn, \
             patch("backend.resolver.os.killpg") as killpg:
            task = asyncio.create_task(resolver.resolve("AAAAAA1"))
            await asyncio.sleep(0)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task

        self.assertTrue(spawn.await_args.kwargs["start_new_session"])
        killpg.assert_called_once_with(4321, signal.SIGKILL)
        process.wait.assert_awaited_once()

    async def test_separate_formats_keep_their_own_headers_and_proxy(self):
        payload = {
            "duration": 90, "title": "Track", "http_headers": {"User-Agent": "shared"},
            "requested_formats": [
                {"url": "https://stream.invalid/video", "vcodec": "avc1", "acodec": "none",
                 "http_headers": {"Referer": "https://video.invalid", "Cookie": "video=1"}},
                {"url": "https://stream.invalid/audio", "vcodec": "none", "acodec": "opus",
                 "http_headers": {"Referer": "https://audio.invalid", "Cookie": "audio=1", "Origin": "bad\r\nInjected: yes"}},
            ],
        }
        process = SimpleNamespace(
            returncode=0, communicate=AsyncMock(return_value=(json.dumps(payload).encode(), b"")),
        )
        with patch("backend.resolver.asyncio.create_subprocess_exec", AsyncMock(return_value=process)):
            resolved = await MediaResolver("python", proxy="http://localhost:1234").resolve("AAAAAA1")
        self.assertEqual(resolved.audio.url, "https://stream.invalid/audio")
        self.assertEqual(resolved.video.url, "https://stream.invalid/video")
        self.assertEqual(resolved.audio.headers, {"user-agent": "shared", "referer": "https://audio.invalid", "cookie": "audio=1"})
        self.assertEqual(resolved.video.headers["cookie"], "video=1")
        self.assertEqual(resolved.audio.proxy, "http://localhost:1234")
        self.assertEqual(resolved.video.proxy, resolved.audio.proxy)
        self.assertEqual((resolved.duration, resolved.title, resolved.seekable), (90, "Track", True))

    async def test_combined_live_format_is_available_without_seeking(self):
        payload = {"url": "https://stream.invalid/live", "vcodec": "h264", "acodec": "aac", "is_live": True}
        process = SimpleNamespace(
            returncode=0, communicate=AsyncMock(return_value=(json.dumps(payload).encode(), b"")),
        )
        with patch("backend.resolver.asyncio.create_subprocess_exec", AsyncMock(return_value=process)):
            resolved = await MediaResolver("python").resolve("AAAAAA1")
        self.assertEqual(resolved.audio.url, resolved.video.url)
        self.assertFalse(resolved.seekable)

    async def test_private_cookie_file_is_passed_to_extractor(self):
        payload = {"url": "https://stream.invalid/media", "vcodec": "h264", "acodec": "aac"}
        process = SimpleNamespace(
            returncode=0, communicate=AsyncMock(return_value=(json.dumps(payload).encode(), b"")),
        )
        with tempfile.TemporaryDirectory() as directory:
            cookies = Path(directory) / "youtube-cookies.txt"
            cookies.write_text("# Netscape HTTP Cookie File\n", encoding="utf-8")
            cookies.chmod(0o600)
            with patch("backend.resolver.asyncio.create_subprocess_exec", AsyncMock(return_value=process)) as spawn:
                await MediaResolver("python", cookies_path=cookies).resolve("AAAAAA1")
        argv = spawn.await_args.args
        self.assertEqual(argv[argv.index("--cookies") + 1], str(cookies))


if __name__ == "__main__":
    unittest.main()
