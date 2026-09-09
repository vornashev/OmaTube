from __future__ import annotations

import asyncio
import os
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
