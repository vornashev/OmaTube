from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from backend.catalog import worker_argv  # noqa: E402
from backend.main import read_proxy_file, single_instance  # noqa: E402


class WorkerPermissionsTest(unittest.TestCase):
    def test_worker_gets_network_and_one_scratch_directory_only(self) -> None:
        argv = worker_argv("/opt/deno", Path("/app/catalog/worker.mjs"), Path("/run/user/1000/omatube/catalog"))
        self.assertEqual(argv[:2], ["/opt/deno", "run"])
        self.assertEqual(argv[-1], "/app/catalog/worker.mjs")
        flags = argv[2:-1]
        self.assertIn("--no-prompt", flags)
        self.assertIn("--cached-only", flags)
        self.assertIn("--allow-read=/run/user/1000/omatube/catalog", flags)
        self.assertIn("--allow-write=/run/user/1000/omatube/catalog", flags)
        self.assertIn("--allow-env=TMPDIR,TMP,TEMP", flags)
        granted = {flag.split("=", 1)[0] for flag in flags if flag.startswith("--allow-")}
        self.assertEqual(granted, {"--allow-net", "--allow-env", "--allow-read", "--allow-write"})
        self.assertFalse(any(flag in {"-A", "--allow-all"} for flag in flags))


class SingleInstanceTest(unittest.TestCase):
    def test_second_backend_does_not_get_the_lock(self) -> None:
        with tempfile.TemporaryDirectory() as runtime, mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": runtime}):
            first = single_instance()
            self.assertIsNotNone(first)
            try:
                self.assertIsNone(single_instance())
            finally:
                os.close(first)
            second = single_instance()
            self.assertIsNotNone(second)
            os.close(second)
            self.assertEqual((Path(runtime) / "omatube").stat().st_mode & 0o777, 0o700)


class ProxyFileTest(unittest.TestCase):
    def test_first_non_comment_line_is_the_proxy(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "proxy"
            self.assertIsNone(read_proxy_file(path))
            path.write_text("# local proxy\n\n  http://127.0.0.1:7897  \nsocks5://ignored\n", encoding="utf-8")
            self.assertEqual(read_proxy_file(path), "http://127.0.0.1:7897")
            path.write_text("# nothing\n", encoding="utf-8")
            self.assertIsNone(read_proxy_file(path))


class DieWithParentTest(unittest.TestCase):
    def test_child_exits_when_its_parent_is_killed(self) -> None:
        # The parent starts a long sleep with die_with_parent, prints its PID and waits; SIGKILL on the parent
        # leaves no chance for cleanup code, so only the kernel's parent-death signal can end the sleep.
        parent_code = textwrap.dedent(f"""
            import subprocess, sys, time
            sys.path.insert(0, {str(ROOT)!r})
            from backend.tools import die_with_parent
            child = subprocess.Popen(["/usr/bin/sleep", "60"], preexec_fn=die_with_parent)
            print(child.pid, flush=True)
            time.sleep(60)
        """)
        parent = subprocess.Popen([sys.executable, "-c", parent_code], stdout=subprocess.PIPE, text=True)
        try:
            child_pid = int(parent.stdout.readline())
            parent.kill(); parent.wait()
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and self._alive(child_pid): time.sleep(0.05)
            self.assertFalse(self._alive(child_pid))
        finally:
            if parent.poll() is None: parent.kill()
            parent.stdout.close()

    @staticmethod
    def _alive(pid: int) -> bool:
        try: state = Path(f"/proc/{pid}/stat").read_text().split()[2]
        except OSError: return False
        return state != "Z"


if __name__ == "__main__":
    unittest.main()
