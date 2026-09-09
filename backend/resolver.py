from __future__ import annotations

import asyncio
import os
import signal
from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any

from .errors import OmaTubeError
from .urls import canonical_video_url

MAX_OUTPUT = 8 * 1024 * 1024
ALLOWED_HEADERS = {"user-agent", "referer"}


@dataclass(frozen=True, slots=True)
class ResolvedAudio:
    url: str
    headers: dict[str, str]
    duration: float | None
    seekable: bool
    title: str | None = None
    author: str | None = None
    thumbnail_url: str | None = None
    canonical_url: str | None = None
    view_count: int | None = None
    like_count: int | None = None


class AudioResolver:
    def __init__(self, python: str | Path, timeout: float = 45.0, proxy: str | None = None) -> None:
        self.python = str(python)
        self.timeout = timeout
        self.proxy = proxy
    @staticmethod
    async def _kill_process(process: asyncio.subprocess.Process) -> None:
        if process.returncode is not None:
            return
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        await process.wait()


    async def resolve_audio(self, video_id: str) -> ResolvedAudio:
        argv = [
            self.python, "-m", "yt_dlp", "--ignore-config", "--dump-single-json",
            "--skip-download", "--no-playlist", "--js-runtimes", "deno",
            "-f", "bestaudio/best",
        ]
        if self.proxy:
            argv.extend(["--proxy", self.proxy])
        argv.extend(["--", canonical_video_url(video_id)])
        process: asyncio.subprocess.Process | None = None
        try:
            process = await asyncio.create_subprocess_exec(
                *argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
                start_new_session=True,
            )
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=self.timeout)
        except asyncio.CancelledError:
            if process is not None:
                await self._kill_process(process)
            raise
        except TimeoutError as exc:
            if process is not None:
                await self._kill_process(process)
            raise OmaTubeError("network_error", "YouTube не ответил за 45 секунд") from exc
        except FileNotFoundError as exc:
            raise OmaTubeError("dependency_missing", "Не найдено Python-окружение yt-dlp") from exc
        if len(stdout) > MAX_OUTPUT or len(stderr) > MAX_OUTPUT:
            raise OmaTubeError("provider_error", "Ответ yt-dlp превышает допустимый размер")
        if process.returncode:
            message = stderr.decode("utf-8", "replace").lower()
            if "sign in" in message or "confirm you’re not a bot" in message or "confirm you're not a bot" in message:
                detail = "YouTube требует авторизацию или проверку клиента"
            elif "po token" in message:
                detail = "YouTube требует PO token"
            elif "not available" in message or "private video" in message:
                detail = "Видео недоступно"
            else:
                detail = "Не удалось получить аудиопоток"
            raise OmaTubeError("unavailable", detail)
        try:
            payload: dict[str, Any] = json.loads(stdout)
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise OmaTubeError("provider_error", "yt-dlp вернул некорректный ответ") from exc
        url = payload.get("url")
        if not isinstance(url, str) or not url.startswith(("https://", "http://")):
            raise OmaTubeError("unavailable", "Аудиопоток отсутствует")
        raw_headers = payload.get("http_headers") or {}
        headers: dict[str, str] = {}
        for key, value in raw_headers.items():
            lowered = str(key).lower()
            if lowered not in ALLOWED_HEADERS or not isinstance(value, str) or "\r" in value or "\n" in value:
                continue
            headers[key] = value
        duration = payload.get("duration")
        thumbnails = payload.get("thumbnails")
        thumbnail = payload.get("thumbnail")
        if not isinstance(thumbnail, str) and isinstance(thumbnails, list):
            thumbnail = next((row.get("url") for row in reversed(thumbnails)
                              if isinstance(row, dict) and isinstance(row.get("url"), str)), None)
        return ResolvedAudio(
            url=url, headers=headers,
            duration=float(duration) if isinstance(duration, (int, float)) else None,
            seekable=not bool(payload.get("is_live")),
            title=payload.get("title") if isinstance(payload.get("title"), str) else None,
            author=next((payload.get(key) for key in ("artist", "uploader", "channel")
                         if isinstance(payload.get(key), str)), None),
            thumbnail_url=thumbnail if isinstance(thumbnail, str) else None,
            canonical_url=payload.get("webpage_url") if isinstance(payload.get("webpage_url"), str) else canonical_video_url(video_id),
            view_count=int(payload["view_count"]) if isinstance(payload.get("view_count"), (int, float)) else None,
            like_count=int(payload["like_count"]) if isinstance(payload.get("like_count"), (int, float)) else None,
        )
