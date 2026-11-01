import unittest

from backend.lyrics import LyricsService, clean_title, parse_lrc, pick


class LyricsTests(unittest.IsolatedAsyncioTestCase):
    def test_clean_title_extracts_artist_and_strips_noise(self):
        self.assertEqual(clean_title("Ночные Огни - Северный ветер (Official Video)", "Some Channel"), ("Ночные Огни", "Северный ветер"))
        self.assertEqual(clean_title("Rivellon", "Borislav Slavov - Topic"), ("Borislav Slavov", "Rivellon"))

    def test_parse_lrc(self):
        rows = parse_lrc("[ar:x]\n[00:12.50] Ветер с севера\n[01:02.5]Город спит\n[00:05]start")
        self.assertEqual(rows, [{"t": 12.5, "text": "Ветер с севера"}, {"t": 62.5, "text": "Город спит"}, {"t": 5.0, "text": "start"}])

    def test_pick_prefers_synced_and_matching_duration(self):
        rows = [{"plainLyrics": "a", "duration": 200}, {"syncedLyrics": "[00:01.00]x", "duration": 199}, {"syncedLyrics": "[00:01.00]y", "duration": 400}]
        self.assertEqual(pick(rows, 200)["duration"], 199)

    async def test_lookup_synced_plain_missing_and_offline(self):
        calls = []
        def fetcher(url, timeout):
            calls.append(url)
            if "/get?" in url: return None
            return [{"syncedLyrics": "[00:01.00]one\n[00:03.00]two", "duration": 100, "artistName": "A", "trackName": "T"}]
        service = LyricsService(fetcher=fetcher)
        result = await service.lookup("A - T", "chan", 100)
        self.assertTrue(result["found"] and result["synced"])
        self.assertEqual([row["text"] for row in result["lines"]], ["one", "two"])
        await service.lookup("A - T", "chan", 100)
        self.assertEqual(len(calls), 2)
        plain = await LyricsService(fetcher=lambda u, t: {"plainLyrics": "x\ny"}).lookup("A - T", "c", None)
        self.assertEqual((plain["synced"], len(plain["lines"])), (False, 2))
        self.assertEqual(await LyricsService(fetcher=lambda u, t: None).lookup("A - T", "c", None), {"found": False})
        def offline(url, timeout): raise OSError("x")
        self.assertEqual((await LyricsService(fetcher=offline).lookup("A - T", "c", None))["found"], False)
