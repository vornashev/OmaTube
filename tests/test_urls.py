import unittest

from backend.errors import OmaTubeError
from backend.urls import normalize_youtube_url, parse_timestamp


class UrlTests(unittest.TestCase):
    def test_supported_video_forms_canonicalize(self):
        cases = {
            "https://youtu.be/BaW_jenozKc?si=tracking": "BaW_jenozKc",
            "https://www.youtube.com/watch?v=BaW_jenozKc&list=PL123456": "BaW_jenozKc",
            "https://music.youtube.com/watch?v=BaW_jenozKc": "BaW_jenozKc",
            "https://youtube.com/shorts/BaW_jenozKc": "BaW_jenozKc",
        }
        for url, video_id in cases.items():
            with self.subTest(url=url):
                value = normalize_youtube_url(url)
                self.assertEqual(value["videoId"], video_id)
                self.assertEqual(value["canonicalUrl"], f"https://www.youtube.com/watch?v={video_id}")

    def test_unsafe_or_unrelated_urls_are_rejected(self):
        for url in ("file:///etc/passwd", "http://youtube.com/watch?v=BaW_jenozKc", "https://evil.example/watch?v=BaW_jenozKc", "https://youtube.com.evil.example/watch?v=BaW_jenozKc"):
            with self.subTest(url=url), self.assertRaises(OmaTubeError):
                normalize_youtube_url(url)

    def test_timestamp_forms(self):
        cases = {"90": 90.0, "90s": 90.0, "1m30s": 90.0, "1h2m3s": 3723.0, "2m": 120.0, "0": None, "": None, "abc": None, "-5": None, "100000": None}
        for raw, expected in cases.items():
            with self.subTest(raw=raw): self.assertEqual(parse_timestamp(raw), expected)

    def test_video_url_carries_start(self):
        self.assertEqual(normalize_youtube_url("https://youtu.be/BaW_jenozKc?t=75")["start"], 75.0)
        self.assertEqual(normalize_youtube_url("https://www.youtube.com/watch?v=BaW_jenozKc&t=1m5s")["start"], 65.0)
        self.assertNotIn("start", normalize_youtube_url("https://www.youtube.com/watch?v=BaW_jenozKc"))


if __name__ == "__main__": unittest.main()
