import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
from pathlib import Path
import socket
import struct
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name: str, path: Path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


host = load("omatube_native_host", ROOT / "bin/omatube-native-host")
cli = load("omatube_cli", ROOT / "bin/omatube")


def frame(value) -> bytes:
    body = json.dumps(value).encode()
    return struct.pack("<I", len(body)) + body


class FakeBackend:
    def __init__(self, preferences=None, fail=None):
        self.requests = []; self.preferences = preferences or {"browserAccept": True, "browserNotify": False}; self.fail = fail

    def __call__(self, request, start_service):
        self.requests.append((request, start_service))
        if request["command"] == "status":
            return {"ok": True, "result": {"state": "playing", "preferences": self.preferences,
                                           "current": {"media": {"title": "Now", "author": "Someone"}}}}
        if self.fail: return {"ok": False, "error": self.fail}
        return {"ok": True, "result": {"entryId": "e"}}


class NativeHostTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); root = Path(self.temporary.name)
        self.environment = patch.dict(os.environ, {"XDG_DATA_HOME": str(root / "data"), "XDG_CONFIG_HOME": str(root / "config"),
                                                   "XDG_RUNTIME_DIR": str(root / "run"), "HOME": str(root / "home")})
        self.environment.start(); self.root = root

    def tearDown(self):
        self.environment.stop(); self.temporary.cleanup()

    def test_framing_round_trip_and_limits(self):
        self.assertEqual(host.read_message(io.BytesIO(frame({"type": "hello"}))), {"type": "hello"})
        self.assertIsNone(host.read_message(io.BytesIO(b"")))
        for raw in (struct.pack("<I", host.MAX_MESSAGE + 1), frame([1]), struct.pack("<I", 10) + b"{}"):
            with self.subTest(raw=raw[:8]), self.assertRaises(host.HostError):
                host.read_message(io.BytesIO(raw))
        output = io.BytesIO(); host.write_message(output, {"ok": True})
        self.assertEqual(host.read_message(io.BytesIO(output.getvalue())), {"ok": True})

    def test_transfer_maps_to_whitelisted_backend_request(self):
        backend = FakeBackend()
        result = host.handle({"type": "transfer", "videoId": "BaW_jenozKc", "start": 312.9, "action": "now",
                              "title": " Title ", "author": "Channel", "channelId": "UC1", "duration": 900,
                              "extensionVersion": "0.2.0"}, backend)
        self.assertEqual(result, {"transferred": True, "command": "play_url", "start": 312.0})
        request, start_service = backend.requests[-1]
        self.assertFalse(start_service)
        self.assertEqual(request, {"command": "play_url", "url": "https://www.youtube.com/watch?v=BaW_jenozKc", "origin": "browser",
                                   "placement": "first", "start": 312.0, "media": {"title": "Title", "author": "Channel", "authorId": "UC1", "duration": 900.0}})
        link = json.loads((self.root / "data/omatube/browser-link.json").read_text())
        self.assertEqual(link["extensionVersion"], "0.2.0"); self.assertIn("lastTransfer", link)
        host.handle({"type": "transfer", "videoId": "BaW_jenozKc", "action": "next", "live": True, "start": 50}, backend)
        self.assertEqual(backend.requests[-1][0], {"command": "enqueue_url", "url": "https://www.youtube.com/watch?v=BaW_jenozKc",
                                                   "origin": "browser", "placement": "next"})

    def test_queue_state_numbers_upcoming_videos_with_eta(self):
        rows = [{"entryId": f"e{i}", "media": {"videoId": v, "duration": d}}
                for i, (v, d) in enumerate([("played000000", 100), ("playing0000", 300), ("next0000000", 60), ("third000000", None), ("fourth00000", 10)])]
        details = {"queue": rows, "current": {"entryId": "e1", "media": rows[1]["media"]}, "duration": 300, "position": 100}
        state = host.queue_state(details)
        self.assertEqual(state["total"], 3)
        self.assertEqual(state["videos"], {"playing0000": {"position": 0}, "next0000000": {"position": 1, "eta": 200},
                                           "third000000": {"position": 2, "eta": 260}, "fourth00000": {"position": 3}})
        idle = host.queue_state({"queue": rows, "current": None})
        self.assertEqual((idle["total"], idle["videos"]["played000000"]), (5, {"position": 1}))

    def test_queue_state_counts_my_queue_after_now_playing(self):
        rows = [{"entryId": "a", "media": {"videoId": "playing0000"}}, {"entryId": "b", "media": {"videoId": "next0000000"}}]
        saved = [{"entryId": "m", "media": {"videoId": "later000000"}}]
        state = host.queue_state({"queue": rows, "mainQueue": saved, "lane": "source", "current": {"entryId": "a"}})
        self.assertEqual((state["total"], state["videos"]["later000000"]), (2, {"position": 2}))
        playing_queue = host.queue_state({"queue": saved, "mainQueue": saved, "lane": "main", "current": {"entryId": "m"}})
        self.assertEqual(playing_queue["total"], 0)

    def test_queue_and_unqueue_messages(self):
        rows = [{"entryId": "a", "media": {"videoId": "BaW_jenozKc"}}, {"entryId": "b", "media": {"videoId": "next0000000"}}]
        class Backend(FakeBackend):
            def __call__(self, request, start_service):
                self.requests.append((request, start_service))
                if request["command"] == "details": return {"ok": True, "result": {"queue": rows, "current": {"entryId": "a", "media": rows[0]["media"]}}}
                return {"ok": True, "result": {}}
        backend = Backend()
        self.assertEqual(host.handle({"type": "queue"}, backend)["videos"]["next0000000"]["position"], 1)
        self.assertEqual(host.handle({"type": "unqueue", "videoId": "next0000000"}, backend), {"removed": True})
        self.assertEqual(backend.requests[-1], ({"command": "queue_remove", "entryId": "b"}, False))
        with self.assertRaises(host.HostError): host.handle({"type": "unqueue", "videoId": "BaW_jenozKc"}, backend)
        rows.append({"entryId": "c", "media": {"videoId": "third000000"}})
        host.handle({"type": "queue_move", "videoId": "third000000", "placement": "next"}, backend)
        self.assertEqual(backend.requests[-1][0], {"command": "queue_move", "entryId": "c", "beforeEntryId": "b"})
        host.handle({"type": "queue_move", "videoId": "next0000000", "placement": "end"}, backend)
        self.assertEqual(backend.requests[-1][0], {"command": "queue_move", "entryId": "b", "beforeEntryId": None})
        with self.assertRaises(host.HostError): host.handle({"type": "queue_move", "videoId": "next0000000", "placement": "now"}, backend)
        down = host.handle({"type": "queue"}, lambda request, start: (_ for _ in ()).throw(host.HostError("backend_down", "x")))
        self.assertEqual(down, {"videos": {}, "total": 0})
        self.assertFalse(any(start for _, start in backend.requests))

    def test_rejects_unknown_messages_and_bad_input(self):
        backend = FakeBackend()
        for message in ({"type": "request", "command": "youtube_auth_import"}, {"type": "transfer", "videoId": "../etc"},
                        {"type": "transfer", "videoId": "BaW_jenozKc", "action": "delete"},
                        {"type": "transfer", "videoId": "BaW_jenozKc", "start": -3}):
            with self.subTest(message=message), self.assertRaises(host.HostError):
                host.handle(message, backend)
        self.assertNotIn("youtube_auth_import", [request["command"] for request, _ in backend.requests])

    def test_backend_errors_are_passed_through(self):
        backend = FakeBackend(fail={"code": "disabled", "message": "off"})
        with self.assertRaises(host.HostError) as raised:
            host.handle({"type": "transfer", "videoId": "BaW_jenozKc"}, backend)
        self.assertEqual(raised.exception.code, "disabled")

    def test_hello_reports_status_without_starting_service(self):
        backend = FakeBackend()
        result = host.handle({"type": "hello"}, backend)
        self.assertEqual((result["backend"], result["accept"], result["current"]["title"]), ("up", True, "Now"))
        self.assertEqual(backend.requests, [({"command": "status"}, False)])
        down = host.handle({"type": "hello"}, lambda request, start: (_ for _ in ()).throw(host.HostError("backend_down", "x")))
        self.assertEqual(down["backend"], "down")

    def test_socket_request_and_missing_backend(self):
        path = self.root / "run/omatube/backend.sock"; path.parent.mkdir(parents=True)
        with patch.object(host.subprocess, "run"), patch.object(host, "BACKEND_START_TIMEOUT", 0.3):
            with self.assertRaises(host.HostError) as raised:
                host.backend_request({"command": "status"})
        self.assertEqual(raised.exception.code, "backend_down")
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); server.bind(str(path)); server.listen(1)
        def serve():
            connection, _ = server.accept()
            with connection:
                request = json.loads(connection.makefile("rb").readline())
                connection.sendall(json.dumps({"ok": True, "result": request}).encode() + b"\n")
        thread = threading.Thread(target=serve); thread.start()
        try: self.assertEqual(host.backend_request({"command": "status"}), {"ok": True, "result": {"command": "status"}})
        finally: thread.join(); server.close()

    def install_host(self) -> Path:
        executable = self.root / "data/omatube/app/bin/omatube-native-host"; executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_text("#!/bin/sh\n"); executable.chmod(0o755)
        return executable

    def profile(self, relative: str, marker: str) -> None:
        directory = self.root / relative; directory.mkdir(parents=True, exist_ok=True); (directory / marker).write_text("")

    def status(self) -> dict:
        output = io.StringIO()
        with patch("sys.stdout", output): self.assertEqual(cli.browser_status(), 0)
        return {row["id"]: row for row in json.loads(output.getvalue())["result"]["browsers"]}

    def setup(self, *args: str) -> None:
        with patch("sys.stdout", io.StringIO()): self.assertEqual(cli.browser_setup_command(list(args)), 0)

    def test_browser_setup_writes_manifests_only_for_installed_browsers(self):
        executable = self.install_host()
        self.profile("config/chromium", "Local State")
        (self.root / "config/vivaldi").mkdir(parents=True)  # a leftover dir without a profile is not a browser
        self.setup()
        manifest = json.loads((self.root / "config/chromium/NativeMessagingHosts/com.vornashev.omatube.json").read_text())
        self.assertEqual(manifest["path"], str(executable))
        self.assertEqual(manifest["allowed_origins"], [f"chrome-extension://{cli.EXTENSION_ID}/"])
        self.assertFalse((self.root / "config/vivaldi/NativeMessagingHosts").exists())
        self.assertFalse((self.root / "home/.mozilla").exists())
        # Zen keeps its profile in $XDG_CONFIG_HOME/zen but reads native hosts from ~/.mozilla.
        self.profile("config/zen", "profiles.ini")
        self.setup()
        zen = json.loads((self.root / "home/.mozilla/native-messaging-hosts/com.vornashev.omatube.json").read_text())
        self.assertEqual(zen["allowed_extensions"], [cli.FIREFOX_EXTENSION_ID])
        self.assertNotIn("allowed_origins", zen)
        self.assertFalse((self.root / "config/zen/native-messaging-hosts").exists())
        # The hosts dir we just made does not make Firefox look installed.
        self.assertNotIn("firefox", self.status())
        self.setup("--remove")
        self.assertFalse((self.root / "config/chromium/NativeMessagingHosts/com.vornashev.omatube.json").exists())
        self.assertFalse((self.root / "home/.mozilla/native-messaging-hosts/com.vornashev.omatube.json").exists())

    def test_browser_status_reports_one_row_per_browser(self):
        self.install_host()
        (self.root / "data/omatube/.installed-version").write_text("0.2.0")
        self.profile("config/zen", "profiles.ini"); self.profile("config/chromium", "Local State"); self.profile("config/BraveSoftware/Brave-Browser", "Local State")
        self.profile("config/thorium", "Local State")
        (self.root / "home/.var/app/org.mozilla.firefox").mkdir(parents=True)
        self.setup()
        (self.root / "config/thorium/NativeMessagingHosts/com.vornashev.omatube.json").unlink()
        (self.root / "data/omatube/browser-link.json").write_text(json.dumps({"browsers": {
            "zen": {"name": "Zen", "lastSeen": "2026-11-01T20:00:00+00:00", "extensionVersion": "0.2.0"},
            "chromium": {"name": "Chromium", "lastSeen": "2026-10-31T20:00:00+00:00", "extensionVersion": "0.1.0"},
            "cromite": {"name": "cromite", "lastSeen": "2026-11-01T19:00:00+00:00", "extensionVersion": "0.2.0"}}}))
        rows = self.status()
        self.assertEqual({key: row["status"] for key, row in rows.items()}, {
            "zen": "connected", "cromite": "connected", "chromium": "outdated", "brave": "ready",
            "thorium": "missing", "firefox-flatpak": "sandboxed"})
        self.assertEqual(list(rows)[:2], ["zen", "cromite"])  # connected first, most recent first
        self.assertEqual(rows["zen"]["hostsDir"], "~/.mozilla/native-messaging-hosts")
        self.assertEqual(rows["cromite"]["kind"], "detected")
        # A broken manifest (e.g. an old host path) counts as missing too.
        target = self.root / "home/.mozilla/native-messaging-hosts/com.vornashev.omatube.json"
        target.write_text(json.dumps({**json.loads(target.read_text()), "path": "/old/host"}))
        self.assertEqual(self.status()["zen"]["status"], "missing")

    def test_custom_dir_is_remembered_and_forgotten(self):
        self.install_host()
        custom = self.root / "opt/cromite"; custom.mkdir(parents=True)
        self.setup("--dir", str(custom))
        target = custom / "NativeMessagingHosts/com.vornashev.omatube.json"
        self.assertTrue(target.is_file())
        target.unlink(); self.setup("--quiet")  # re-created on the next start
        self.assertTrue(target.is_file())
        self.assertEqual(self.status()[f"custom:{custom.resolve()}"]["status"], "ready")
        gecko = self.root / "opt/fork"; gecko.mkdir(parents=True); (gecko / "profiles.ini").write_text("")
        self.setup("--dir", str(gecko))
        self.assertIn("allowed_extensions", json.loads((gecko / "native-messaging-hosts/com.vornashev.omatube.json").read_text()))
        with patch("sys.stdout", io.StringIO()): cli.browser_setup_command(["--forget", str(custom)])
        self.assertFalse(target.exists())
        self.assertNotIn(f"custom:{custom.resolve()}", self.status())
        with patch("sys.stderr", io.StringIO()): self.assertEqual(cli.browser_setup_command(["--dir"]), 2)

    def test_host_identifies_browser_from_parent_executable(self):
        links = {100: "/opt/zen-browser-bin/zen-bin", 200: "/opt/google/chrome-beta/chrome", 300: "/usr/bin/bash",
                 301: "/usr/lib/chromium/chromium", 400: "/usr/bin/mystery (deleted)"}
        stats = {300: "300 (bash) S 301 0 0"}
        readlink = lambda path: links[int(path.split("/")[2])] if int(path.split("/")[2]) in links else (_ for _ in ()).throw(OSError())
        reader = lambda self, *args, **kwargs: stats[int(str(self).split("/")[2])]
        with patch("os.readlink", readlink), patch.object(Path, "read_text", reader):
            self.assertEqual(host.identify_browser(100), ("zen", "Zen"))
            self.assertEqual(host.identify_browser(200), ("google-chrome-beta", "Chrome Beta"))
            self.assertEqual(host.identify_browser(300), ("chromium", "Chromium"))
            self.assertEqual(host.identify_browser(400), ("mystery", "mystery"))
            self.assertIsNone(host.identify_browser(999))

    def test_link_is_recorded_per_browser(self):
        host.record_link({"extensionVersion": "0.2.0"}, True, ("zen", "Zen"))
        host.record_link({"extensionVersion": "0.1.0"}, False, ("chromium", "Chromium"))
        link = json.loads((self.root / "data/omatube/browser-link.json").read_text())
        self.assertEqual(link["browsers"]["zen"]["extensionVersion"], "0.2.0")
        self.assertIn("lastTransfer", link["browsers"]["zen"])
        self.assertNotIn("lastTransfer", link["browsers"]["chromium"])
        result = host.handle({"type": "hello"}, FakeBackend(), ("zen", "Zen"))
        self.assertEqual((result["browserId"], result["browserName"]), ("zen", "Zen"))

    def test_host_and_cli_agree_on_browser_ids(self):
        known = {row[0] for row in cli.KNOWN_BROWSERS}
        identified = {value[0] for value in host.BROWSER_EXECUTABLES.values()} | {value[0] for value in host.CHROME_DIRS.values()}
        self.assertEqual(identified - known, set())

    def test_extension_id_matches_manifest_key(self):
        import base64, hashlib
        key = json.loads((ROOT / "browser-extension/src/manifest.json").read_text())["key"]
        digest = hashlib.sha256(base64.b64decode(key)).hexdigest()[:32]
        self.assertEqual("".join(chr(ord("a") + int(char, 16)) for char in digest), cli.EXTENSION_ID)


if __name__ == "__main__": unittest.main()
