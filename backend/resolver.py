from __future__ import annotations

import asyncio
import os
import re
import signal
import time
from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any

from .auth import secure_cookie_file
from .cache import ByteTTLCache
from .errors import OmaTubeError
from .net import NetStats
from .tools import system_tool
from .urls import canonical_video_url

MAX_OUTPUT = 8 * 1024 * 1024
RESOLVE_FIELDS = (
    "%(.{requested_formats,url,acodec,vcodec,http_headers,duration,thumbnails,thumbnail,"
    "chapters,description,channel_id,is_live,title,artist,uploader,channel,webpage_url,"
    "view_count,like_count})j"
)
# Storyboard sprite sheets are always listed first among the formats (sb3…sb0).
STORYBOARD_FIELDS = "%(formats.:4.{format_id,rows,columns,width,height,fragments})j"
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
    author_id: str | None = None
    description: str | None = None
    chapters: tuple[dict[str, Any], ...] = ()
    storyboard: dict[str, Any] | None = None


def parse_storyboard(value: Any) -> dict[str, Any] | None:
    """Pick the 160 px sheet (or the largest one up to 320 px) for timeline previews."""
    if not isinstance(value, list): return None
    sheets = []
    for row in value:
        if not isinstance(row, dict) or not str(row.get("format_id", "")).startswith("sb"): continue
        fragments = row.get("fragments")
        rows, columns, width, height = (row.get(key) for key in ("rows", "columns", "width", "height"))
        if not isinstance(fragments, list) or not fragments: continue
        if not all(isinstance(number, int) and number > 0 for number in (rows, columns, width, height)): continue
        urls = [item.get("url") for item in fragments if isinstance(item, dict)]
        interval = fragments[0].get("duration") if isinstance(fragments[0], dict) else None
        if not all(isinstance(url, str) and url.startswith("https://i.ytimg.com/") for url in urls): continue
        if not isinstance(interval, (int, float)) or interval <= 0: continue
        sheets.append({"urls": urls[:400], "rows": rows, "columns": columns, "width": width, "height": height,
                       "interval": float(interval) / (rows * columns)})
    usable = [sheet for sheet in sheets if sheet["width"] <= 320]
    if not usable: return None
    return next((sheet for sheet in usable if sheet["width"] == 160), max(usable, key=lambda sheet: sheet["width"]))


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
        self.hedge_delays = (3.0, 3.0, 3.0, 0.0)
        self.cache_ttl = 1200.0
        self.stats = NetStats(slow_seconds=8.0)
        self._cache = ByteTTLCache(16 * 1024 * 1024, 64, self.cache_ttl)
        self._inflight: dict[tuple[str, int], asyncio.Task[ResolvedMedia]] = {}
        self._prefetched: set[asyncio.Task[ResolvedMedia]] = set()
    @staticmethod
    def _json_line(lines: list[bytes], index: int, strict: bool = False) -> Any:
        if index >= len(lines): return None
        try:
            return json.loads(lines[index])
        except (json.JSONDecodeError, UnicodeDecodeError):
            if strict: raise
            return None

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
        key = (video_id, self.max_video_height)
        cached = self._cache.get(key)
        if cached and time.monotonic() - cached[0] < self.cache_ttl:
            return cached[1]
        task = self._inflight.get(key)
        if task is None or task.done():
            task = asyncio.ensure_future(self._resolve_uncached(video_id))
            self._inflight[key] = task
            task.add_done_callback(lambda finished, key=key: self._finish(key, finished))
        else:
            self._prefetched.discard(task)
        try:
            return await asyncio.shield(task)
        except asyncio.CancelledError:
            # A superseded request stops its extractor; a background prefetch keeps running.
            if not task.done() and task not in self._prefetched:
                task.cancel()
                await asyncio.wait({task})
            raise

    def _finish(self, key: tuple[str, int], task: asyncio.Task[ResolvedMedia]) -> None:
        if self._inflight.get(key) is task:
            self._inflight.pop(key, None)
        if not task.cancelled() and task.exception() is None:
            result = task.result()
            self._cache.put(key, (time.monotonic(), result), len(repr(result).encode()))

    def prefetch(self, video_id: str) -> None:
        key = (video_id, self.max_video_height)
        cached = self._cache.get(key)
        if (cached and time.monotonic() - cached[0] < self.cache_ttl) or key in self._inflight:
            return
        task = asyncio.ensure_future(self._resolve_uncached(video_id))
        self._prefetched.add(task)
        self._inflight[key] = task
        task.add_done_callback(lambda finished, key=key: self._finish(key, finished))
        task.add_done_callback(lambda finished: (self._prefetched.discard(finished), finished.cancelled() or finished.exception()))

    async def _resolve_uncached(self, video_id: str) -> ResolvedMedia:
        started = time.monotonic()
        try:
            media = await self._resolve_attempts(video_id)
        except OmaTubeError as error:
            if error.code == "network_error": self.stats.record(time.monotonic() - started, False)
            raise
        self.stats.record(time.monotonic() - started, True)
        return media

    async def _resolve_attempts(self, video_id: str) -> ResolvedMedia:
        if os.environ.get("OMATUBE_RESOLVE_HLS") == "1":
            return await self._hedged(video_id, skip_hls=False)
        try:
            return await self._hedged(video_id, skip_hls=True)
        except OmaTubeError as error:
            if error.code != "unavailable":
                raise
            return await self._hedged(video_id, skip_hls=False)

    async def _hedged(self, video_id: str, skip_hls: bool) -> ResolvedMedia:
        # Some connections to YouTube silently hang. Start a fresh attempt every few
        # seconds and keep whichever answers first instead of waiting out each timeout.
        tasks: list[asyncio.Task[ResolvedMedia]] = []
        first_error: BaseException | None = None
        try:
            for delay in self.hedge_delays:
                tasks.append(asyncio.ensure_future(self._resolve(video_id, skip_hls)))
                done, pending = await asyncio.wait(tasks, timeout=delay, return_when=asyncio.FIRST_COMPLETED)
                for task in done:
                    if task.exception() is None:
                        return task.result()
                    first_error = first_error or task.exception()
                    tasks.remove(task)
                if first_error is not None and isinstance(first_error, OmaTubeError) and first_error.code in {"unavailable", "auth_required", "po_token_required"}:
                    raise first_error
            while tasks:
                done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                for task in done:
                    tasks.remove(task)
                    if task.exception() is None:
                        return task.result()
                    first_error = first_error or task.exception()
            raise first_error or OmaTubeError("unavailable", "Не удалось получить медиапоток")
        finally:
            for task in tasks:
                if not task.done():
                    task.cancel()
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)

    async def _resolve(self, video_id: str, skip_hls: bool) -> ResolvedMedia:
        argv = [
            # Print only the fields we read: the full dump can exceed MAX_OUTPUT
            # because automatic_captions lists every auto-translated language.
            self.python, "-m", "yt_dlp", "--ignore-config", "--print", RESOLVE_FIELDS, "--print", STORYBOARD_FIELDS,
            "--skip-download", "--no-playlist", "--js-runtimes", f"deno:{system_tool('deno')}",
            "--socket-timeout", "8", "--extractor-retries", "3",
            *(["--extractor-args", "youtube:skip=hls"] if skip_hls else []),
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
        lines = stdout.splitlines()
        try:
            payload: dict[str, Any] = self._json_line(lines, 0, strict=True) if len(lines) > 1 and lines[0].startswith(b"{") \
                and lines[0].rstrip().endswith(b"}") else json.loads(stdout)
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
        chapters = tuple(
            {"start": float(row["start_time"]), "end": float(row["end_time"]) if isinstance(row.get("end_time"), (int, float)) else None,
             "title": str(row.get("title") or "")[:200]}
            for row in (payload.get("chapters") or [])[:200]
            if isinstance(row, dict) and isinstance(row.get("start_time"), (int, float))
        )
        description = payload.get("description")
        return ResolvedMedia(
            author_id=payload.get("channel_id") if isinstance(payload.get("channel_id"), str) else None,
            description=description[:6000] if isinstance(description, str) else None,
            chapters=chapters,
            storyboard=parse_storyboard(self._json_line(lines, 1)),
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
