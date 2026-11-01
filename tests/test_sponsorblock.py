import asyncio
from pathlib import Path
import tempfile
import unittest

from backend.player import Player
from backend.sponsorblock import SponsorBlock, hash_prefix, parse_segments
from backend.storage import Storage
from test_player import FakeMpv, FakeResolver, media


class SeekMpv(FakeMpv):
    def __init__(self): super().__init__(); self.seeks = []
    async def seek(self, value): self.seeks.append(value)


class SponsorBlockTests(unittest.IsolatedAsyncioTestCase):
    def test_hash_prefix_is_four_hex_chars(self):
        self.assertEqual(hash_prefix("dQw4w9WgXcQ"), hash_prefix("dQw4w9WgXcQ"))
        self.assertEqual(len(hash_prefix("abc")), 4)

    def test_parse_filters_other_videos_and_invalid_rows(self):
        payload = [{"videoID": "v1", "segments": [
            {"segment": [10, 20], "category": "sponsor", "actionType": "skip", "UUID": "a"},
            {"segment": [30, 20], "category": "sponsor", "actionType": "skip"},
            {"segment": [1, 2], "category": "unknown", "actionType": "skip"},
            {"segment": [5, 6], "category": "intro", "actionType": "mute"}]},
            {"videoID": "other", "segments": [{"segment": [1, 2], "category": "sponsor", "actionType": "skip"}]}]
        rows = parse_segments(payload, "v1")
        self.assertEqual([(row["start"], row["end"], row["category"]) for row in rows], [(10.0, 20.0, "sponsor")])

    async def test_fetch_caches_and_survives_errors(self):
        calls = []
        def fetcher(url, timeout):
            calls.append(url)
            return [{"videoID": "v1", "segments": [{"segment": [1, 5], "category": "sponsor", "actionType": "skip", "UUID": "u"}]}]
        service = SponsorBlock(fetcher=fetcher)
        self.assertEqual(len(await service.segments("v1", ["sponsor"])), 1)
        await service.segments("v1", ["sponsor"])
        self.assertEqual(len(calls), 1)
        self.assertIn(f"/{hash_prefix('v1')}?", calls[0])
        def broken(url, timeout): raise OSError("offline")
        self.assertEqual(await SponsorBlock(fetcher=broken).segments("v2", ["sponsor"]), [])
        self.assertEqual(await service.segments("v1", []), [])


class PlayerSponsorTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.storage = Storage(Path(self.temp.name) / "db.sqlite3")
        self.mpv = SeekMpv(); self.player = Player(self.storage, FakeResolver(), self.mpv, lambda: None)
        self.player.can_seek = True
        self.player.segments = [{"start": 10.0, "end": 20.0, "category": "sponsor", "id": "s1"},
                                {"start": 50.0, "end": 60.0, "category": "outro", "id": "o1"}]
        self.player.sponsor_actions = {"sponsor": "skip", "outro": "ask"}

    async def asyncTearDown(self):
        self.storage.close(); self.temp.cleanup()

    async def test_skip_then_undo_returns_and_ignores_segment(self):
        await self.player._check_segments(12.0)
        self.assertEqual(self.mpv.seeks, [20.0])
        self.assertEqual(self.player.status()["sponsor"]["lastSkip"]["seconds"], 10.0)
        self.assertEqual(self.player.status()["sponsor"]["saved"], 10.0)
        await self.player.sponsor_undo()
        self.assertEqual(self.mpv.seeks, [20.0, 10.0])
        await self.player._check_segments(12.0)
        self.assertEqual(self.mpv.seeks, [20.0, 10.0])
        self.assertEqual(self.player.status()["sponsor"]["saved"], 0.0)

    async def test_ask_sets_pending_and_dismiss_ignores(self):
        await self.player._check_segments(55.0)
        self.assertEqual(self.player.status()["sponsor"]["pending"]["id"], "o1")
        self.assertEqual(self.mpv.seeks, [])
        await self.player.sponsor_dismiss()
        await self.player._check_segments(55.0)
        self.assertIsNone(self.player.status()["sponsor"]["pending"])

    async def test_ask_skip_command_seeks_to_end(self):
        await self.player._check_segments(55.0)
        await self.player.sponsor_skip()
        self.assertEqual(self.mpv.seeks, [60.0])
