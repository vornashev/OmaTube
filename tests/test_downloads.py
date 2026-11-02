import asyncio
from pathlib import Path
import sys
import tempfile
import unittest

from backend.downloads import DownloadManager, explain_failure, parse_progress
from backend.storage import Storage

MEDIA = {"videoId": "AAAAAAAAAAA", "source": "youtube", "title": "Episode", "author": "Kuji",
         "canonicalUrl": "https://www.youtube.com/watch?v=AAAAAAAAAAA"}


class DownloadTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.storage = Storage(self.root / "library.sqlite3")
        self.script = "import sys,time\nprint('download:100/1000/NA/50.0/18.0',flush=True)\nprint(sys.argv[1],flush=True)\nopen(sys.argv[1],'w').write('x'*10)\n"
        self.manager = self.make(lambda item: [sys.executable, "-c", self.script, str(self.root / "dl" / "out.opus")])

    def make(self, factory):
        (self.root / "dl").mkdir(exist_ok=True)
        return DownloadManager(self.storage, self.root / "dl", sys.executable, None, None, lambda: None, command_factory=factory)

    async def asyncTearDown(self):
        await self.manager.shutdown(); self.storage.close(); self.temp.cleanup()

    def test_parse_progress_and_failure_messages(self):
        self.assertEqual(parse_progress("download:412/664/NA/5100.5/49"), {"downloaded": 412, "total": 664, "speed": 5100.5, "eta": 49.0})
        self.assertEqual(parse_progress("download:5/NA/900/NA/NA")["total"], 900)
        self.assertIsNone(parse_progress("[download] noise"))
        self.assertIn("403", explain_failure("ERROR: HTTP Error 403: Forbidden"))

    async def test_successful_download_records_file_and_size(self):
        row = self.manager.add(MEDIA, "audio")
        self.assertEqual(row["state"], "queued")
        await asyncio.gather(*self.manager.tasks.values())
        done = self.storage.download(row["id"])
        self.assertEqual((done["state"], done["size"]), ("done", 10))
        self.assertTrue(done["filepath"].endswith("out.opus"))
        summary = self.manager.summary()
        self.assertEqual((summary["used"], summary["active"]), (10, 0))
        await self.manager.remove(row["id"], delete_file=True)
        self.assertFalse((self.root / "dl" / "out.opus").exists())
        self.assertEqual(self.storage.downloads(), [])

    async def test_failure_retry_and_duplicate_guard(self):
        self.manager = self.make(lambda item: [sys.executable, "-c", "import sys;sys.stderr.write('ERROR: HTTP Error 403');sys.exit(1)"])
        row = self.manager.add(MEDIA, "video")
        self.assertEqual(self.manager.add(MEDIA, "video")["id"], row["id"])
        await asyncio.gather(*self.manager.tasks.values())
        failed = self.storage.download(row["id"])
        self.assertEqual(failed["state"], "failed"); self.assertIn("403", failed["error"])
        self.manager.retry(row["id"])
        self.assertIn(self.storage.download(row["id"])["state"], {"queued", "running"})
        await asyncio.gather(*self.manager.tasks.values())

    async def test_pause_resume_and_cancel(self):
        self.manager = self.make(lambda item: [sys.executable, "-c", "import time;print('download:1/10/NA/1.0/9.0',flush=True);time.sleep(30)"])
        row = self.manager.add(MEDIA, "audio")
        for _ in range(100):
            await asyncio.sleep(0.05)
            if self.manager.processes.get(row["id"]): break
        self.manager.pause(row["id"])
        self.assertEqual(self.storage.download(row["id"])["state"], "paused")
        self.manager.resume(row["id"])
        self.assertEqual(self.storage.download(row["id"])["state"], "running")
        await self.manager.cancel(row["id"])
        self.assertIsNone(self.storage.download(row["id"]))

    def test_brief_counts_active_and_failed_with_overall_progress(self):
        self.assertEqual(self.manager.brief(), {"active": 0, "failed": 0, "progress": None})
        self.storage.create_download("a", MEDIA, "audio"); self.storage.update_download("a", state="running", downloaded=300, total=1000)
        self.storage.create_download("b", {**MEDIA, "videoId": "BBBBBBBBBBB"}, "audio"); self.storage.update_download("b", state="paused", downloaded=500, total=1000)
        self.storage.create_download("c", {**MEDIA, "videoId": "CCCCCCCCCCC"}, "audio"); self.storage.update_download("c", state="failed")
        self.assertEqual(self.manager.brief(), {"active": 2, "failed": 1, "progress": 0.4})

    def test_restart_marks_interrupted_downloads_failed(self):
        self.storage.create_download("x", MEDIA, "audio"); self.storage.update_download("x", state="running")
        self.make(lambda item: [])
        self.assertEqual(self.storage.download("x")["state"], "failed")
