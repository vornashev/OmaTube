from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
import signal
from typing import Any

from .auth import secure_cookie_file
from .errors import OmaTubeError

CHANNELS_URL = "https://www.youtube.com/feed/channels"
MAX_OUTPUT = 16 * 1024 * 1024


def parse_channels(payload: dict[str, Any]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    channels: list[dict[str, Any]] = []
    for entry in payload.get("entries") or []:
        if not isinstance(entry, dict): continue
        channel_id = entry.get("channel_id") or entry.get("id")
        if not isinstance(channel_id, str) or not channel_id.startswith("UC") or channel_id in seen: continue
        seen.add(channel_id)
        thumbs = [t for t in entry.get("thumbnails") or [] if isinstance(t, dict) and t.get("url")]
        thumb = max(thumbs, key=lambda t: t.get("width") or 0)["url"] if thumbs else None
        channels.append({
            "source": "youtube", "kind": "channel", "id": channel_id,
            "title": str(entry.get("title") or entry.get("channel") or channel_id),
            "thumbnailUrl": thumb, "canonicalUrl": f"https://www.youtube.com/channel/{channel_id}",
        })
    return channels


async def fetch_channels(python: Path | str, cookies: Path | None, proxy: str | None, timeout: float = 90.0) -> list[dict[str, Any]]:
    if cookies is None or not secure_cookie_file(cookies):
        raise OmaTubeError("auth_required", "Для импорта подписок войдите в аккаунт в настройках")
    argv = [str(python), "-m", "yt_dlp", "--ignore-config", "--flat-playlist", "--dump-single-json",
            "--socket-timeout", "8", "--extractor-retries", "3", "--cookies", str(cookies)]
    if proxy: argv.extend(["--proxy", proxy])
    argv.extend(["--", CHANNELS_URL])
    process: asyncio.subprocess.Process | None = None
    try:
        process = await asyncio.create_subprocess_exec(*argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, start_new_session=True)
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout)
    except (asyncio.CancelledError, TimeoutError) as exc:
        if process is not None and process.returncode is None:
            try: os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            await process.wait()
        if isinstance(exc, TimeoutError): raise OmaTubeError("network_error", "YouTube не ответил за 90 секунд") from exc
        raise
    except FileNotFoundError as exc:
        raise OmaTubeError("dependency_missing", "Не найдено Python-окружение yt-dlp") from exc
    if process.returncode:
        message = stderr.decode("utf-8", "replace").lower()
        if "sign in" in message or "login" in message or "cookies" in message:
            raise OmaTubeError("auth_required", "YouTube не принял вход; обновите cookies в настройках")
        raise OmaTubeError("provider_error", "Не удалось получить список подписок")
    if len(stdout) > MAX_OUTPUT: raise OmaTubeError("provider_error", "Ответ yt-dlp превышает допустимый размер")
    try: payload = json.loads(stdout)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise OmaTubeError("provider_error", "yt-dlp вернул некорректный ответ") from exc
    return parse_channels(payload if isinstance(payload, dict) else {})
