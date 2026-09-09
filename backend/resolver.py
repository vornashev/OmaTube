from __future__ import annotations

import asyncio
import os
import re
import signal
from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any

from .auth import secure_cookie_file
from .errors import OmaTubeError
from .urls import canonical_video_url

MAX_OUTPUT = 8 * 1024 * 1024
VIDEO_QUALITIES = frozenset({360, 480, 720, 1080, 1440, 2160})
HEADER_NAME = re.compile(r"[!#$%&'*+.^_`|~0-9a-z-]+")


@dataclass(frozen=True, slots=True)
class ResolvedStream:
    url: str
    headers: dict[str, str]
    proxy: str | None = None


@dataclass(frozen=True, slots=True)
class ResolvedMedia:
    audio: ResolvedStream
    duration: float | None
    seekable: bool
    video: ResolvedStream | None = None
    title: str | None = None
    author: str | None = None
    thumbnail_url: str | None = None
    canonical_url: str | None = None
    view_count: int | None = None
    like_count: int | None = None


class MediaResolver:
    def __init__(
        self,
        python: str | Path,
        timeout: float = 45.0,
        proxy: str | None = None,
        cookies_path: Path | None = None,
        max_video_height: int = 1080,
    ) -> None:
        self.python = str(python)
        self.timeout = timeout
        self.proxy = proxy
        self.cookies_path = cookies_path
        if type(max_video_height) is not int or max_video_height not in VIDEO_QUALITIES:
            raise ValueError("unsupported video quality")
        self.max_video_height = max_video_height
    @staticmethod
    async def _kill_process(process: asyncio.subprocess.Process) -> None:
        if process.returncode is not None:
            return
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        await process.wait()


    async def resolve(self, video_id: str) -> ResolvedMedia:
        argv = [
            self.python, "-m", "yt_dlp", "--ignore-config", "--dump-single-json",
            "--skip-download", "--no-playlist", "--js-runtimes", "deno",
            "-f", (
                f"bestvideo[height<={self.max_video_height}]+bestaudio/"
                f"best[height<={self.max_video_height}]/bestaudio"
            ),
        ]
        if self.cookies_path and secure_cookie_file(self.cookies_path):
            argv.extend(["--cookies", str(self.cookies_path)])
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
            if "confirm your age" in message or "sign in" in message:
                detail = "YouTube требует входа; импортируйте cookies авторизованного Chromium в настройках"
                code = "auth_required"
            elif "confirm you’re not a bot" in message or "confirm you're not a bot" in message:
                detail = "YouTube запросил проверку клиента; обновите cookies в настройках"
                code = "auth_required"
            elif "po token" in message:
                detail = "YouTube требует PO token для этого потока"
                code = "po_token_required"
            elif "429" in message or "too many requests" in message:
                detail = "YouTube временно ограничил частоту запросов"
                code = "rate_limited"
            elif "not available" in message or "private video" in message:
                detail = "Видео недоступно"
                code = "unavailable"
            else:
                detail = "Не удалось получить медиапоток"
                code = "unavailable"
            raise OmaTubeError(code, detail)
        try:
            payload: dict[str, Any] = json.loads(stdout)
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise OmaTubeError("provider_error", "yt-dlp вернул некорректный ответ") from exc
        formats = payload.get("requested_formats") or [payload]
        audio_format = next((row for row in formats if row.get("acodec") not in {None, "none"}), None)
        video_format = next((row for row in formats if row.get("vcodec") not in {None, "none"}), None)
        if audio_format is None:
            raise OmaTubeError("unavailable", "Аудиопоток отсутствует")

        def stream(row: dict[str, Any]) -> ResolvedStream:
            url = row.get("url")
            if not isinstance(url, str) or not url.startswith(("https://", "http://")):
                raise OmaTubeError("unavailable", "Медиапоток отсутствует")
            raw_headers = {
                str(key).lower(): value
                for values in (payload.get("http_headers") or {}, row.get("http_headers") or {})
                for key, value in values.items()
            }
            headers = {
                key: value for key, value in raw_headers.items()
                if HEADER_NAME.fullmatch(key) and isinstance(value, str)
                and "\r" not in value and "\n" not in value
            }
            return ResolvedStream(url, headers, self.proxy)
        duration = payload.get("duration")
        thumbnails = payload.get("thumbnails")
        thumbnail = payload.get("thumbnail")
        if not isinstance(thumbnail, str) and isinstance(thumbnails, list):
            thumbnail = next((row.get("url") for row in reversed(thumbnails)
                              if isinstance(row, dict) and isinstance(row.get("url"), str)), None)
        return ResolvedMedia(
            audio=stream(audio_format),
            video=stream(video_format) if video_format else None,
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
