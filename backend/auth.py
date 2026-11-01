from __future__ import annotations

import asyncio
import hashlib
import os
import shutil
import sqlite3
from pathlib import Path
import signal
import stat
import tempfile
from typing import Any

from .errors import OmaTubeError

MAX_COOKIE_FILE = 2 * 1024 * 1024
SUPPORTED_BROWSERS = {"chromium": "chromium+gnomekeyring"}
AUTH_COOKIE_NAMES = {
    "SAPISID",
    "__Secure-1PAPISID",
    "__Secure-3PAPISID",
    "LOGIN_INFO",
}
PROBE_URL = "https://www.youtube.com/watch?v=L10l1tg9bu4"


def secure_cookie_file(path: Path) -> bool:
    try:
        info = path.lstat()
    except OSError:
        return False
    return (
        stat.S_ISREG(info.st_mode)
        and info.st_uid == os.getuid()
        and stat.S_IMODE(info.st_mode) & 0o077 == 0
        and info.st_size <= MAX_COOKIE_FILE
    )


def filter_youtube_cookies(content: str) -> tuple[str, int, bool]:
    rows: list[str] = []
    authenticated = False
    for raw in content.splitlines():
        line = raw.strip("\r\n")
        value = line[len("#HttpOnly_"):] if line.startswith("#HttpOnly_") else line
        if not value or value.startswith("#"):
            continue
        fields = value.split("\t")
        if len(fields) != 7:
            continue
        domain = fields[0].lstrip(".").lower()
        if domain != "youtube.com" and not domain.endswith(".youtube.com"):
            continue
        rows.append(line)
        if fields[5] in AUTH_COOKIE_NAMES and fields[6]:
            authenticated = True
    filtered = "# Netscape HTTP Cookie File\n# YouTube-only cookies managed by OmaTube.\n"
    if rows:
        filtered += "\n".join(rows) + "\n"
    return filtered, len(rows), authenticated


CHROMIUM_DIR = Path.home() / ".config" / "chromium"
CHROMIUM_EPOCH = 11644473600


def chromium_safe_storage_key() -> bytes:
    """AES key from the keyring item that belongs to Chromium itself.

    Other Chromium-based apps (VS Code, Electron apps) also store a "Chromium Safe Storage"
    item; yt-dlp takes the first one by label and may pick the wrong secret.
    """
    import secretstorage
    connection = secretstorage.dbus_init()
    try:
        collection = secretstorage.get_default_collection(connection)
        if collection.is_locked(): collection.unlock()
        items = list(collection.search_items({"application": "chromium"}))
        if not items: raise OmaTubeError("auth_import_error", "В связке ключей нет пароля Chromium")
        password = items[0].get_secret()
    finally:
        connection.close()
    return hashlib.pbkdf2_hmac("sha1", password, b"saltysalt", 1, 16)


def decrypt_chromium_value(blob: bytes, key: bytes, host_key: str, strip_hash: bool) -> str | None:
    from Cryptodome.Cipher import AES
    if not blob: return ""
    if blob[:3] not in (b"v10", b"v11"): return blob.decode("utf-8", "replace")
    data = blob[3:]
    if not data or len(data) % 16: return None
    try:
        plain = AES.new(key, AES.MODE_CBC, b" " * 16).decrypt(data)
        plain = plain[:-plain[-1]]
        if strip_hash:
            if plain[:32] != hashlib.sha256(host_key.encode()).digest(): return None
            plain = plain[32:]
        return plain.decode("utf-8")
    except (ValueError, UnicodeDecodeError, IndexError):
        return None


def read_chromium_cookies(profile: Path, key: bytes) -> list[str]:
    source = profile / "Cookies"
    if not source.exists(): source = profile / "Network" / "Cookies"
    if not source.exists(): return []
    with tempfile.TemporaryDirectory(prefix="omatube-cookies-") as temp:
        copy = Path(temp) / "Cookies"
        shutil.copy2(source, copy)
        db = sqlite3.connect(copy)
        try:
            row = db.execute("SELECT value FROM meta WHERE key='version'").fetchone()
            strip_hash = bool(row and int(row[0]) >= 24)
            rows = db.execute("SELECT host_key,path,is_secure,expires_utc,name,value,encrypted_value,is_httponly FROM cookies "
                              "WHERE host_key LIKE '%youtube.com'").fetchall()
        finally:
            db.close()
    lines = ["# Netscape HTTP Cookie File"]
    for host, path, secure, expires, name, value, encrypted, httponly in rows:
        if encrypted:
            value = decrypt_chromium_value(bytes(encrypted), key, host, strip_hash)
            if value is None: continue
        expiry = max(0, int(expires / 1_000_000 - CHROMIUM_EPOCH)) if expires else 0
        lines.append("\t".join([("#HttpOnly_" if httponly else "") + host, "TRUE" if host.startswith(".") else "FALSE", path,
                                "TRUE" if secure else "FALSE", str(expiry), name, value]))
    return lines


def import_chromium_profiles(root: Path = CHROMIUM_DIR, key: bytes | None = None) -> str:
    key = key or chromium_safe_storage_key()
    best, best_score = "", -1
    for profile in sorted([root / "Default", *root.glob("Profile *")]):
        lines = read_chromium_cookies(profile, key)
        content = "\n".join(lines) + "\n"
        _, count, authenticated = filter_youtube_cookies(content)
        score = count + (10_000 if authenticated else 0)
        if score > best_score: best, best_score = content, score
    return best


class YouTubeAuth:
    def __init__(self, python: str | Path, config_dir: Path) -> None:
        self.python = str(python)
        self.path = config_dir / "youtube-cookies.txt"

    def status(self) -> dict[str, Any]:
        if not self.path.exists():
            return {"configured": False, "authenticated": False, "cookieCount": 0, "browser": "chromium"}
        if not secure_cookie_file(self.path):
            return {
                "configured": False,
                "authenticated": False,
                "cookieCount": 0,
                "browser": "chromium",
                "error": "Файл cookies должен принадлежать текущему пользователю и иметь права 600",
            }
        try:
            content = self.path.read_text(encoding="utf-8")
        except OSError:
            return {
                "configured": False,
                "authenticated": False,
                "cookieCount": 0,
                "browser": "chromium",
                "error": "Не удалось прочитать файл cookies",
            }
        _, count, authenticated = filter_youtube_cookies(content)
        return {"configured": count > 0, "authenticated": authenticated, "cookieCount": count, "browser": "chromium"}

    @staticmethod
    async def _terminate(process: asyncio.subprocess.Process) -> None:
        if process.returncode is not None:
            return
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        await process.wait()

    async def import_from_browser(self, browser: str) -> dict[str, Any]:
        if browser not in SUPPORTED_BROWSERS:
            raise OmaTubeError("invalid_request", "Неподдерживаемый браузер")
        try:
            content = await asyncio.to_thread(import_chromium_profiles)
            filtered, count, authenticated = filter_youtube_cookies(content)
            if count and authenticated:
                self._write(filtered)
                return self.status()
        except Exception:
            pass
        return await self._import_with_ytdlp(browser)

    def _write(self, filtered: str) -> None:
        descriptor, name = tempfile.mkstemp(prefix=".youtube-cookies-", suffix=".tmp", dir=self.path.parent)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle: handle.write(filtered)
            os.chmod(name, 0o600)
            os.replace(name, self.path)
        finally:
            Path(name).unlink(missing_ok=True)

    async def _import_with_ytdlp(self, browser: str) -> dict[str, Any]:
        descriptor, temporary_name = tempfile.mkstemp(prefix=".youtube-cookies-", suffix=".tmp", dir=self.path.parent)
        os.close(descriptor)
        temporary = Path(temporary_name)
        temporary.unlink()
        process: asyncio.subprocess.Process | None = None
        try:
            process = await asyncio.create_subprocess_exec(
                self.python, "-m", "yt_dlp", "--ignore-config",
                "--cookies-from-browser", SUPPORTED_BROWSERS[browser],
                "--cookies", str(temporary),
                "--simulate", "--skip-download", "--no-playlist",
                "--", PROBE_URL,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.PIPE,
                start_new_session=True,
            )
            _, stderr = await asyncio.wait_for(process.communicate(), 45)
        except asyncio.CancelledError:
            if process is not None:
                await self._terminate(process)
            raise
        except TimeoutError as exc:
            if process is not None:
                await self._terminate(process)
            raise OmaTubeError("network_error", "Импорт cookies не завершился за 45 секунд") from exc
        except FileNotFoundError as exc:
            raise OmaTubeError("dependency_missing", "Не найдено окружение yt-dlp") from exc
        try:
            if not temporary.exists() or temporary.stat().st_size > MAX_COOKIE_FILE:
                detail = stderr.decode("utf-8", "replace").strip()
                raise OmaTubeError("auth_import_error", detail[-500:] or "Chromium не вернул cookies")
            filtered, count, _ = filter_youtube_cookies(temporary.read_text(encoding="utf-8"))
            if count == 0:
                detail = stderr.decode("utf-8", "replace").strip()
                raise OmaTubeError("auth_import_error", detail[-500:] or "В профиле Chromium нет cookies YouTube")
            temporary.write_text(filtered, encoding="utf-8")
            temporary.chmod(0o600)
            temporary.replace(self.path)
            return self.status()
        except UnicodeError as exc:
            raise OmaTubeError("auth_import_error", "Chromium вернул повреждённый файл cookies") from exc
        finally:
            temporary.unlink(missing_ok=True)

    async def clear(self) -> dict[str, Any]:
        self.path.unlink(missing_ok=True)
        return self.status()
