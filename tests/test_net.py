import asyncio
from pathlib import Path
import http.server
import tempfile
import threading
import unittest
import urllib.request

from backend.net import HttpClient, ImageCache, ImageServer, NetStats, Reply, allowed_image_url, downsized

JPEG = b"\xff\xd8\xff\xe0" + b"0" * 64


class Handler(http.server.BaseHTTPRequestHandler):
    hits = 0
    def log_message(self, *args): pass
    def do_GET(self):
        Handler.hits += 1
        if self.headers.get("If-None-Match") == '"v1"':
            self.send_response(304); self.end_headers(); return
        self.send_response(200); self.send_header("ETag", '"v1"'); self.send_header("Content-Length", "5"); self.end_headers()
        self.wfile.write(b"hello")


class StubClient:
    def __init__(self, replies):
        self.replies = replies; self.calls = []
    def get(self, url, timeout=8.0, headers=None, max_bytes=0):
        self.calls.append(url)
        return self.replies.get(url) or Reply(404, {}, b"")


class HelperTests(unittest.TestCase):
    def test_allowed_hosts(self):
        self.assertTrue(allowed_image_url("https://i.ytimg.com/vi/abc/hqdefault.jpg"))
        self.assertTrue(allowed_image_url("https://yt3.ggpht.com/x=s88"))
        self.assertFalse(allowed_image_url("http://i.ytimg.com/vi/a/b.jpg"))
        self.assertFalse(allowed_image_url("https://evil.example/ytimg.com"))
        self.assertFalse(allowed_image_url("https://i.ytimg.com.evil.example/a.jpg"))

    def test_downsized_only_small_video_thumbnails(self):
        url = "https://i.ytimg.com/vi/abc123/maxresdefault.jpg?sqp=x"
        self.assertEqual(downsized(url, 300), "https://i.ytimg.com/vi/abc123/mqdefault.jpg")
        self.assertEqual(downsized(url, 600), url)
        webp = "https://i.ytimg.com/vi_webp/abc123/hqdefault.webp"
        self.assertEqual(downsized(webp, 200), "https://i.ytimg.com/vi_webp/abc123/mqdefault.webp")
        self.assertEqual(downsized("https://yt3.ggpht.com/a=s88", 50), "https://yt3.ggpht.com/a=s88")

    def test_net_stats_slow_detection(self):
        stats = NetStats()
        stats.record(1.0); stats.record(2.0)
        self.assertFalse(stats.slow)
        stats.record(9.0); stats.record(12.0)
        self.assertTrue(stats.slow)
        fails = NetStats()
        fails.record(1, False); fails.record(1, False)
        self.assertTrue(fails.slow)


class ClientTests(unittest.TestCase):
    def test_revalidation_reuses_body_on_304(self):
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            client = HttpClient()
            url = f"http://127.0.0.1:{server.server_address[1]}/feed"
            first = client.get_revalidated(url)
            second = client.get_revalidated(url)
            self.assertEqual((first.body, second.body, second.status), (b"hello", b"hello", 200))
            self.assertEqual(Handler.hits, 2)
        finally:
            server.shutdown()


class ImageTests(unittest.IsolatedAsyncioTestCase):
    async def test_cache_dedupes_downloads_and_falls_back_to_original(self):
        with tempfile.TemporaryDirectory() as temp:
            original = "https://i.ytimg.com/vi/abc123/maxresdefault.jpg"
            client = StubClient({original: Reply(200, {"content-type": "image/jpeg"}, JPEG)})
            cache = ImageCache(Path(temp), client)
            first, second = await asyncio.gather(cache.get(original, 300), cache.get(original, 300))
            self.assertEqual(first[0], second[0])
            self.assertEqual(first[1], "image/jpeg")
            self.assertEqual(client.calls, ["https://i.ytimg.com/vi/abc123/mqdefault.jpg", original])
            await cache.get(original, 300)
            self.assertEqual(len(client.calls), 2)

    async def test_rejects_foreign_hosts_and_evicts_oldest(self):
        with tempfile.TemporaryDirectory() as temp:
            cache = ImageCache(Path(temp), StubClient({}), max_bytes=100)
            with self.assertRaises(ValueError): await cache.get("https://example.com/a.jpg")
            for index, age in enumerate((100, 200, 300)):
                path = Path(temp) / f"f{index}"; path.write_bytes(b"x" * 60)
                import os; os.utime(path, (age, age))
            cache.evict()
            self.assertEqual(sorted(entry.name for entry in Path(temp).iterdir()), ["f2"])

    async def test_server_serves_cached_image_over_http(self):
        with tempfile.TemporaryDirectory() as temp:
            url = "https://i.ytimg.com/vi/abc123/hqdefault.jpg"
            cache = ImageCache(Path(temp), StubClient({url: Reply(200, {"content-type": "image/jpeg"}, JPEG)}))
            server = ImageServer(cache, 0)
            port = await server.start()
            try:
                def fetch(target):
                    try:
                        with urllib.request.urlopen(f"http://127.0.0.1:{port}/img?u={target}", timeout=5) as response:
                            return response.status, response.read()
                    except urllib.error.HTTPError as error:
                        return error.code, b""
                self.assertEqual(await asyncio.to_thread(fetch, url), (200, JPEG))
                self.assertEqual((await asyncio.to_thread(fetch, "https://example.com/a.jpg"))[0], 403)
            finally:
                await server.stop()


if __name__ == "__main__":
    unittest.main()
