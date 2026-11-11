from pathlib import Path
import shutil
import subprocess
import unittest

from backend.cache import ByteTTLCache


class CacheTests(unittest.TestCase):
    def test_byte_budget_and_lru(self):
        cache = ByteTTLCache(10, 3, 30)
        cache.put("a", "first", 4)
        cache.put("b", "second", 4)
        self.assertEqual(cache.get("a"), "first")
        cache.put("c", "third", 4)
        self.assertIsNone(cache.get("b"))
        self.assertEqual(cache.bytes, 8)
        cache.put("large", "oversized", 11)
        self.assertIsNone(cache.get("large"))
        self.assertLessEqual(cache.bytes, 10)

    def test_expiry_without_another_request(self):
        now = [0]
        cache = ByteTTLCache(100, 2, 30, clock=lambda: now[0])
        cache.put("a", "old", 10)
        now[0] = 29
        self.assertEqual(cache.get("a"), "old")
        now[0] = 31
        cache.prune()
        self.assertEqual(len(cache), 0)
        self.assertEqual(cache.bytes, 0)

    @unittest.skipUnless(shutil.which("node"), "Node.js is not installed")
    def test_catalog_cache(self):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run([shutil.which("node"), "--test", str(root / "catalog/cache.test.mjs")],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
