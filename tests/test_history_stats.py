from datetime import date, timedelta
from pathlib import Path
import tempfile
import time
import unittest

from backend.errors import OmaTubeError
from backend.storage import Storage


def media(video_id, title="T", author="A", duration=100):
    return {"videoId": video_id, "source": "youtube", "title": title, "author": author, "duration": duration}


class HistoryStatsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.storage = Storage(Path(self.temp.name) / "library.sqlite3")

    def tearDown(self):
        self.storage.close(); self.temp.cleanup()

    def test_history_carries_progress_total_and_can_remove(self):
        play = self.storage.add_history(media("a"))
        self.storage.add_history(media("b"))
        self.storage.save_progress("a", 40, 100)
        page = self.storage.collection("history")
        self.assertEqual(page["total"], 2)
        by_id = {item["videoId"]: item for item in page["items"]}
        self.assertEqual(by_id["a"]["watchProgress"], {"position": 40, "duration": 100})
        self.assertNotIn("watchProgress", by_id["b"])
        self.storage.remove_history_entry(play)
        self.assertEqual(self.storage.collection("history")["total"], 1)

    def test_continue_watching_skips_finished_and_barely_started(self):
        for video_id, position in (("a", 40), ("b", 99), ("c", 5)):
            self.storage.upsert_media(media(video_id)); self.storage.save_progress(video_id, position, 100)
        self.assertEqual([row["videoId"] for row in self.storage.continue_watching()], ["a"])

    def test_stats_totals_bars_and_tops(self):
        self.storage.add_history(media("a", "Song A", "Chan 1")); self.storage.add_history(media("a", "Song A", "Chan 1")); self.storage.add_history(media("b", "Song B", "Chan 2"))
        today = time.time(); yesterday = today - 86400
        self.storage.add_listening("a", 3600, today); self.storage.add_listening("b", 1800, yesterday)
        self.storage.add_sponsor_saving(30, today)
        week = self.storage.stats("week")
        self.assertEqual(week["totalSeconds"], 5400)
        self.assertEqual(week["plays"], 3)
        self.assertEqual(week["channels"], 2)
        self.assertEqual((week["sponsorSeconds"], week["sponsorSegments"]), (30, 1))
        self.assertEqual(len(week["bars"]), 7)
        self.assertAlmostEqual(week["bars"][-1]["seconds"], 3600)
        self.assertEqual(week["topChannels"][0], {"title": "Chan 1", "seconds": 3600})
        self.assertEqual((week["topTracks"][0]["title"], week["topTracks"][0]["plays"]), ("Song A", 2))
        self.assertEqual(self.storage.stats("all")["totalSeconds"], 5400)
        self.assertEqual(len(self.storage.stats("month")["bars"]), 6)
        with self.assertRaises(OmaTubeError): self.storage.stats("year")

    def test_previous_period_for_delta(self):
        old = time.mktime((date.today() - timedelta(days=10)).timetuple()) + 3600
        self.storage.upsert_media(media("a")); self.storage.add_listening("a", 600, old)
        week = self.storage.stats("week")
        self.assertEqual((week["totalSeconds"], week["previousSeconds"]), (0, 600))

    def test_sessions_roundtrip_and_limit(self):
        with self.assertRaises(OmaTubeError): self.storage.save_session("x", [])
        saved = self.storage.save_session("Вечер", [media("a", duration=60), media("b", duration=40)])
        self.assertEqual((saved["count"], saved["duration"]), (2, 100))
        self.assertEqual([row["name"] for row in self.storage.sessions()], ["Вечер"])
        self.assertEqual([row["videoId"] for row in self.storage.session_media(saved["id"])], ["a", "b"])
        self.storage.delete_session(saved["id"])
        with self.assertRaises(OmaTubeError): self.storage.session_media(saved["id"])
        for index in range(55): self.storage.save_session(f"s{index}", [media("a")])
        self.assertEqual(len(self.storage.sessions()), 50)


if __name__ == "__main__":
    unittest.main()
