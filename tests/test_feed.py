import asyncio
from pathlib import Path
import tempfile
import unittest

from backend.feed import FeedService, parse_feed
from backend.storage import Storage

ATOM = b"""<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
 <author><name>kuji podcast</name></author>
 <entry><yt:videoId>AAAAAAAAAAA</yt:videoId><yt:channelId>UC1</yt:channelId><title>Episode 231</title>
  <link rel="alternate" href="https://www.youtube.com/watch?v=AAAAAAAAAAA"/><author><name>kuji podcast</name></author>
  <published>2026-10-04T10:00:00+00:00</published>
  <media:group><media:thumbnail url="https://i.invalid/a.jpg"/><media:community><media:statistics views="769000"/></media:community></media:group></entry>
 <entry><yt:videoId>BBBBBBBBBBB</yt:videoId><title>Episode 230</title><published>2026-09-27T10:00:00+00:00</published></entry>
</feed>"""


class FeedTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.storage = Storage(Path(self.temp.name) / "library.sqlite3")

    def tearDown(self):
        self.storage.close(); self.temp.cleanup()

    def test_parse_feed(self):
        parsed = parse_feed(ATOM)
        self.assertEqual(parsed["title"], "kuji podcast")
        self.assertEqual([row["videoId"] for row in parsed["items"]], ["AAAAAAAAAAA", "BBBBBBBBBBB"])
        self.assertEqual(parsed["items"][0]["viewCount"], 769000)
        self.assertEqual(parse_feed(b"not xml"), {"title": None, "items": []})

    async def test_fetch_returns_none_on_network_error(self):
        def broken(channel_id, timeout): raise OSError("offline")
        self.assertIsNone(await FeedService(fetcher=broken).fetch("UC1"))
        self.assertEqual((await FeedService(fetcher=lambda c, t: ATOM).fetch("UC1"))["items"][0]["title"], "Episode 231")

    def test_subscription_feed_new_counts_and_seen(self):
        self.storage.subscribe({"id": "UC1", "title": "kuji podcast", "thumbnailUrl": None, "kind": "channel", "source": "youtube"})
        items = parse_feed(ATOM)["items"]
        self.assertEqual(self.storage.add_feed_items("UC1", items, initial=True), 2)
        self.assertEqual(self.storage.new_count(), 0)
        newer = [{**items[0], "videoId": "CCCCCCCCCCC", "title": "Episode 232", "publishedAt": "2026-10-05T10:00:00+00:00"}]
        self.assertEqual(self.storage.add_feed_items("UC1", newer), 1)
        self.assertEqual(self.storage.add_feed_items("UC1", newer), 0)
        feed = self.storage.feed()
        self.assertEqual([row["videoId"] for row in feed["items"]][0], "CCCCCCCCCCC")
        self.assertTrue(feed["items"][0]["isNew"]); self.assertEqual(feed["newCount"], 1)
        self.assertEqual(self.storage.subscriptions()[0]["newCount"], 1)
        self.storage.mark_feed_seen()
        self.assertEqual(self.storage.new_count(), 0)
        self.storage.unsubscribe("UC1")
        self.assertEqual(self.storage.feed()["items"], [])
        self.assertFalse(self.storage.is_subscribed("UC1"))

    def test_progress_roundtrip(self):
        self.storage.save_progress("AAAAAAAAAAA", 120, 600)
        self.storage.save_progress("AAAAAAAAAAA", 300, 600)
        self.assertEqual(self.storage.progress_for(["AAAAAAAAAAA", "zzz"]), {"AAAAAAAAAAA": {"position": 300, "duration": 600}})


class HiddenChannelTests(unittest.TestCase):
    def test_hide_unhide_and_watch_later_lookup(self):
        with tempfile.TemporaryDirectory() as temp:
            storage = Storage(Path(temp) / "library.sqlite3")
            storage.hide_channel("UC1", "Spam"); storage.hide_channel("UC1", "Spam"); storage.hide_channel("UC2", "Other")
            self.assertEqual({row["id"] for row in storage.hidden_channels()}, {"UC1", "UC2"})
            storage.unhide_channel("UC1")
            self.assertEqual([row["id"] for row in storage.hidden_channels()], ["UC2"])
            storage.unhide_channel(None)
            self.assertEqual(storage.hidden_channels(), [])
            self.assertIsNone(storage.playlist_id_by_name("Смотреть позже"))
            created = storage.create_playlist("Смотреть позже")["id"]
            self.assertEqual(storage.playlist_id_by_name("Смотреть позже"), created)
            storage.close()
