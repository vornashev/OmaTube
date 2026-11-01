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


class StoryboardTests(unittest.TestCase):
    def test_prefers_160px_sheet_and_computes_frame_interval(self):
        from backend.resolver import parse_storyboard
        sheet = lambda fid, width, rows: {"format_id": fid, "rows": rows, "columns": rows, "width": width, "height": width * 9 // 16,
                                          "fragments": [{"url": f"https://i.ytimg.com/sb/x/{fid}.jpg", "duration": 50.0}]}
        result = parse_storyboard([sheet("sb3", 48, 10), sheet("sb1", 160, 5), sheet("sb0", 320, 3), {"format_id": "251"}])
        self.assertEqual(result["width"], 160)
        self.assertEqual(result["interval"], 2.0)
        self.assertIsNone(parse_storyboard([{"format_id": "sb1", "rows": 5, "columns": 5, "width": 160, "height": 90,
                                             "fragments": [{"url": "https://evil.invalid/x.jpg", "duration": 50}]}]))
        self.assertIsNone(parse_storyboard("NA"))


if __name__ == "__main__":
    unittest.main()


class HedgedResolveTests(unittest.IsolatedAsyncioTestCase):
    async def test_second_attempt_wins_when_first_hangs(self):
        from backend.resolver import ResolvedMedia, ResolvedStream
        resolver = MediaResolver("python")
        resolver.hedge_delays = (0.05, 0.05, 0.0)
        calls = []
        cancelled = []

        async def fake(video_id, skip_hls):
            calls.append(len(calls))
            index = len(calls) - 1
            try:
                if index == 0:
                    await asyncio.Future()
                return ResolvedMedia(ResolvedStream(f"https://stream.invalid/{index}", {}), 10, True)
            except asyncio.CancelledError:
                cancelled.append(index)
                raise

        resolver._resolve = fake
        media = await resolver.resolve("AAAAAA1")
        self.assertEqual(media.audio.url, "https://stream.invalid/1")
        self.assertEqual(cancelled, [0])

    async def test_unavailable_error_stops_hedging(self):
        from backend.errors import OmaTubeError
        resolver = MediaResolver("python")
        resolver.hedge_delays = (0.05, 0.05, 0.0)
        calls = []

        async def fake(video_id, skip_hls):
            calls.append(skip_hls)
            raise OmaTubeError("unavailable", "Видео недоступно")

        resolver._resolve = fake
        with self.assertRaises(OmaTubeError):
            await resolver.resolve("AAAAAA1")
        self.assertEqual(calls, [True, False])


class ResolveCacheTests(unittest.IsolatedAsyncioTestCase):
    async def test_cache_and_prefetch_share_one_extractor_run(self):
        from backend.resolver import ResolvedMedia, ResolvedStream
        resolver = MediaResolver("python")
        calls = []

        async def fake(video_id):
            calls.append(video_id)
            await asyncio.sleep(0.02)
            return ResolvedMedia(ResolvedStream(f"https://stream.invalid/{video_id}", {}), 10, True)

        resolver._resolve_uncached = fake
        resolver.prefetch("AAAAAA1")
        first = await resolver.resolve("AAAAAA1")
        second = await resolver.resolve("AAAAAA1")
        self.assertIs(first, second)
        self.assertEqual(calls, ["AAAAAA1"])
        resolver.max_video_height = 720
        await resolver.resolve("AAAAAA1")
        self.assertEqual(calls, ["AAAAAA1", "AAAAAA1"])

    async def test_cancelled_waiter_stops_its_run_but_idle_prefetch_keeps_running(self):
        resolver = MediaResolver("python")
        cancelled = []

        async def fake(video_id):
            try:
                await asyncio.Future()
            except asyncio.CancelledError:
                cancelled.append(video_id)
                raise

        resolver._resolve_uncached = fake
        waiter = asyncio.create_task(resolver.resolve("AAAAAA1"))
        await asyncio.sleep(0.01)
        waiter.cancel()
        await asyncio.gather(waiter, return_exceptions=True)
        await asyncio.sleep(0.01)
        self.assertEqual(cancelled, ["AAAAAA1"])
        resolver.prefetch("BBBBBB2")
        await asyncio.sleep(0.01)
        self.assertEqual(cancelled, ["AAAAAA1"])
        for task in list(resolver._inflight.values()):
            task.cancel()
