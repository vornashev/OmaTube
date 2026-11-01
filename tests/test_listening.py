import asyncio
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from test_player import FakeMpv, FakeResolver, media
from backend.player import Player
from backend.storage import Storage


class ListeningTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.storage = Storage(Path(self.temp.name) / "db.sqlite3")
        self.player = Player(self.storage, FakeResolver(), FakeMpv(), lambda: None)
        self.player.queue = [{"entryId": "e1", "media": media("AAAAAA1")}, {"entryId": "e2", "media": media("BBBBBB2")}]
        self.player.current_id = "e1"; self.player.state = "playing"; self.player.buffering = False

    async def asyncTearDown(self):
        self.storage.close(); self.temp.cleanup()

    def tick(self, clock, seconds):
        clock.append(clock[-1] + seconds)
        self.player._track_listening()

    def test_accumulates_wall_time_only_while_playing_and_flushes_per_track(self):
        clock = [1000.0]
        with mock.patch("backend.player.time.monotonic", side_effect=lambda: clock[-1]):
            self.player._track_listening()
            for _ in range(10): self.tick(clock, 1)
            self.player.state = "paused"; self.tick(clock, 30)
            self.player.state = "playing"; self.tick(clock, 1)
            for _ in range(3): self.tick(clock, 1)
            self.player.current_id = "e2"
            self.tick(clock, 1)
            self.player._flush_listening()
        rows = dict(self.storage.db.execute("SELECT video_id,SUM(seconds) FROM listening GROUP BY video_id").fetchall())
        self.assertAlmostEqual(rows["AAAAAA1"], 13, delta=1)
        self.assertNotIn("BBBBBB2", rows)

    def test_long_gaps_are_not_counted(self):
        clock = [0.0]
        with mock.patch("backend.player.time.monotonic", side_effect=lambda: clock[-1]):
            self.player._track_listening(); self.tick(clock, 60); self.tick(clock, 2)
            self.player._flush_listening()
        total = self.storage.db.execute("SELECT COALESCE(SUM(seconds),0) FROM listening").fetchone()[0]
        self.assertEqual(total, 2)


if __name__ == "__main__":
    unittest.main()
