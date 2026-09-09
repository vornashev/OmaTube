from pathlib import Path
import os
import tempfile
import unittest

from backend.auth import filter_youtube_cookies, secure_cookie_file


class YouTubeAuthTests(unittest.TestCase):
    def test_filter_keeps_only_youtube_rows_and_detects_signed_in_session(self):
        source = """# Netscape HTTP Cookie File
.google.com\tTRUE\t/\tTRUE\t0\tSID\tsecret-google
.youtube.com\tTRUE\t/\tTRUE\t0\tPREF\tguest
#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t0\tSAPISID\tsigned-in
example.com\tFALSE\t/\tFALSE\t0\tother\tsecret
"""
        filtered, count, authenticated = filter_youtube_cookies(source)
        self.assertEqual(count, 2)
        self.assertTrue(authenticated)
        self.assertIn("#HttpOnly_.youtube.com", filtered)
        self.assertNotIn("secret-google", filtered)
        self.assertNotIn("example.com", filtered)

    def test_empty_authentication_marker_is_not_signed_in(self):
        source = ".youtube.com\tTRUE\t/\tTRUE\t0\tSAPISID\t\n"
        _, count, authenticated = filter_youtube_cookies(source)
        self.assertEqual(count, 1)
        self.assertFalse(authenticated)


    def test_cookie_file_must_be_private_regular_file_owned_by_user(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cookies.txt"
            path.write_text("# Netscape HTTP Cookie File\n", encoding="utf-8")
            path.chmod(0o600)
            self.assertTrue(secure_cookie_file(path))
            path.chmod(0o644)
            self.assertFalse(secure_cookie_file(path))
            path.unlink()
            target = Path(directory) / "target"
            target.write_text("cookies", encoding="utf-8")
            target.chmod(0o600)
            os.symlink(target, path)
            self.assertFalse(secure_cookie_file(path))


if __name__ == "__main__":
    unittest.main()
