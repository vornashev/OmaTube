import hashlib
from pathlib import Path
import sqlite3
import tempfile
import unittest

from Cryptodome.Cipher import AES

from backend.auth import filter_youtube_cookies, import_chromium_profiles, decrypt_chromium_value

KEY = hashlib.pbkdf2_hmac("sha1", b"test-secret", b"saltysalt", 1, 16)


def encrypt(value: str, host: str, key: bytes = KEY, with_hash: bool = True) -> bytes:
    plain = (hashlib.sha256(host.encode()).digest() if with_hash else b"") + value.encode()
    pad = 16 - len(plain) % 16
    return b"v11" + AES.new(key, AES.MODE_CBC, b" " * 16).encrypt(plain + bytes([pad]) * pad)


def make_profile(root: Path, name: str, cookies: list[tuple[str, str, str, bytes]]) -> None:
    profile = root / name
    profile.mkdir()
    db = sqlite3.connect(profile / "Cookies")
    db.execute("CREATE TABLE meta(key TEXT, value TEXT)")
    db.execute("INSERT INTO meta VALUES('version','24')")
    db.execute("CREATE TABLE cookies(host_key TEXT, path TEXT, is_secure INT, expires_utc INT, name TEXT, value TEXT, encrypted_value BLOB, is_httponly INT)")
    for host, cookie_name, value, blob in cookies:
        db.execute("INSERT INTO cookies VALUES(?,?,?,?,?,?,?,?)", (host, "/", 1, 13_470_000_000_000_000, cookie_name, value, blob, 1))
    db.commit(); db.close()


class ChromiumCookieTests(unittest.TestCase):
    def test_roundtrip_and_wrong_key(self):
        blob = encrypt("abc", ".youtube.com")
        self.assertEqual(decrypt_chromium_value(blob, KEY, ".youtube.com", True), "abc")
        self.assertIsNone(decrypt_chromium_value(blob, b"x" * 16, ".youtube.com", True))

    def test_prefers_authenticated_profile_and_skips_undecryptable(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            wrong = encrypt("old", ".youtube.com", b"y" * 16)
            make_profile(root, "Default", [(".youtube.com", "SAPISID", "", encrypt("secret", ".youtube.com")),
                                           (".youtube.com", "STALE", "", wrong),
                                           (".google.com", "SAPISID", "", encrypt("g", ".google.com"))])
            make_profile(root, "Profile 2", [(".youtube.com", "YSC", "", encrypt("guest", ".youtube.com"))])
            content = import_chromium_profiles(root, KEY)
            filtered, count, authenticated = filter_youtube_cookies(content)
            self.assertTrue(authenticated)
            self.assertEqual(count, 1)
            self.assertIn("SAPISID\tsecret", filtered)
            self.assertNotIn("STALE", filtered)


if __name__ == "__main__":
    unittest.main()
