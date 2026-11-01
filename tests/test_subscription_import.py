import asyncio
import os
from pathlib import Path
import stat
import tempfile
import unittest

from backend.errors import OmaTubeError
from backend.subscription_import import fetch_channels, parse_channels

PAYLOAD = {"entries": [
    {"id": "UC1", "title": "kuji podcast", "thumbnails": [{"url": "https://i/a.jpg", "width": 88}, {"url": "https://i/b.jpg", "width": 176}]},
    {"id": "UC1", "title": "dup"},
    {"id": "notchannel", "title": "x"},
    {"channel_id": "UC2", "title": "Lofi Girl"},
    "junk",
]}


class ParseTests(unittest.TestCase):
    def test_parse_channels_dedupes_and_picks_largest_thumbnail(self):
        channels = parse_channels(PAYLOAD)
        self.assertEqual([c["id"] for c in channels], ["UC1", "UC2"])
        self.assertEqual(channels[0]["thumbnailUrl"], "https://i/b.jpg")
        self.assertEqual(channels[1]["thumbnailUrl"], None)

    def test_empty(self):
        self.assertEqual(parse_channels({}), [])


class FetchTests(unittest.IsolatedAsyncioTestCase):
    async def test_requires_cookies(self):
        with self.assertRaises(OmaTubeError) as ctx:
            await fetch_channels("python3", None, None)
        self.assertEqual(ctx.exception.code, "auth_required")

    async def test_failing_extractor_maps_to_error(self):
        with tempfile.TemporaryDirectory() as temp:
            cookies = Path(temp) / "cookies.txt"; cookies.write_text("# x\n"); cookies.chmod(0o600)
            script = Path(temp) / "fake.sh"; script.write_text("#!/bin/sh\necho 'ERROR: Sign in' >&2\nexit 1\n"); script.chmod(0o700)
            with self.assertRaises(OmaTubeError) as ctx:
                await fetch_channels(script, cookies, None)
            self.assertEqual(ctx.exception.code, "auth_required")


if __name__ == "__main__":
    unittest.main()
