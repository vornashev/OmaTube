from __future__ import annotations

import asyncio
from collections import deque
from dataclasses import dataclass
import hashlib
import json
import logging
import os
from pathlib import Path
import re
import threading
import time
from typing import Any
from urllib.parse import parse_qs, urlparse

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from .cache import ByteTTLCache

LOGGER = logging.getLogger(__name__)
WARM_URLS = (
    "https://www.youtube.com/", "https://i.ytimg.com/", "https://yt3.ggpht.com/",
    "https://sponsor.ajay.app/", "https://lrclib.net/",
)
IMAGE_HOST_SUFFIXES = ("ytimg.com", "ggpht.com", "googleusercontent.com")
DEFAULT_IMAGE_PORT = 47865
MAX_IMAGE = 4 * 1024 * 1024
VI_THUMB = re.compile(r"^(/vi(?:_webp)?/[A-Za-z0-9_-]+/)(?:maxresdefault|sddefault|hqdefault)(\.(?:jpg|webp))$")


@dataclass
class Reply:
    status: int
    headers: dict[str, str]
    body: bytes


class NetStats:
    """Rolling view of how healthy the connection to YouTube is."""

    def __init__(self, window: int = 6, slow_seconds: float = 6.0) -> None:
        self.samples: deque[tuple[float, bool]] = deque(maxlen=window)
        self.slow_seconds = slow_seconds

    def record(self, seconds: float, ok: bool = True) -> None:
        self.samples.append((seconds, ok))

    @property
    def slow(self) -> bool:
        if len(self.samples) < 2: return False
        recent = list(self.samples)[-3:]
        failures = sum(1 for _, ok in recent if not ok)
        durations = [seconds for seconds, ok in recent if ok]
        average = sum(durations) / len(durations) if durations else 0
        return failures >= 2 or (len(durations) >= 2 and average > self.slow_seconds)


class HttpClient:
    """One pooled, keep-alive session shared by every plain-HTTP call of the backend."""

    def __init__(self, proxy: str | None = None, user_agent: str = "OmaTube", pool_size: int = 16) -> None:
        self.session = requests.Session()
        self.session.trust_env = False
        self.session.headers["User-Agent"] = user_agent
        retry = Retry(total=2, backoff_factor=0.25, status_forcelist=(502, 503, 504), allowed_methods=("GET", "HEAD"))
        adapter = HTTPAdapter(pool_connections=8, pool_maxsize=pool_size, max_retries=retry)
        self.session.mount("https://", adapter)
        self.session.mount("http://", adapter)
        if proxy: self.session.proxies = {"http": proxy, "https": proxy}
        self._validators = ByteTTLCache(16 * 1024 * 1024, 256, 7200)
        self._lock = threading.Lock()

    def get(self, url: str, timeout: float = 8.0, headers: dict[str, str] | None = None, max_bytes: int = 2 * 1024 * 1024) -> Reply:
        with self.session.get(url, headers=headers, timeout=(min(timeout, 5.0), timeout), stream=True) as response:
            body = bytearray()
            for chunk in response.iter_content(64 * 1024):
                body.extend(chunk)
                if len(body) > max_bytes: raise ValueError("Ответ слишком велик")
            return Reply(response.status_code, {key.lower(): value for key, value in response.headers.items()}, bytes(body))

    def get_revalidated(self, url: str, timeout: float = 8.0) -> Reply:
        """GET with ETag / Last-Modified: an unchanged feed costs a 304 instead of a full body."""
        with self._lock:
            known = self._validators.get(url)
        headers: dict[str, str] = {}
        if known:
            if known[0].get("etag"): headers["If-None-Match"] = known[0]["etag"]
            if known[0].get("last-modified"): headers["If-Modified-Since"] = known[0]["last-modified"]
        reply = self.get(url, timeout, headers)
        if reply.status == 304 and known: return Reply(200, known[0], known[1])
        if reply.status == 200 and (reply.headers.get("etag") or reply.headers.get("last-modified")):
            with self._lock:
                validators = {k: v for k, v in reply.headers.items() if k in {"etag", "last-modified"}}
                self._validators.put(url, (validators, reply.body), len(reply.body) + len(url.encode()) + 256)
        return reply

    def prune_cache(self) -> None:
        with self._lock:
            self._validators.prune()

    def json(self, url: str, timeout: float = 6.0, not_found: Any = None, headers: dict[str, str] | None = None) -> Any:
        reply = self.get(url, timeout, {"Accept": "application/json", **(headers or {})})
        if reply.status == 404: return not_found
        if reply.status >= 400: raise OSError(f"HTTP {reply.status}")
        return json.loads(reply.body)

    def warm(self) -> int:
        """Open TLS connections ahead of the first real request."""
        ready = 0
        for url in WARM_URLS:
            try:
                self.session.head(url, timeout=(4, 4), allow_redirects=False).close(); ready += 1
            except requests.RequestException:
                continue
        return ready


def allowed_image_url(url: str) -> bool:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    return parsed.scheme == "https" and not parsed.username and not parsed.port and any(
        host == suffix or host.endswith("." + suffix) for suffix in IMAGE_HOST_SUFFIXES)


def downsized(url: str, width: int) -> str:
    """Video thumbnails come as 480-1280px images; small cards only need mqdefault (320x180)."""
    if not width or width > 340: return url
    parsed = urlparse(url)
    match = VI_THUMB.match(parsed.path)
    if not match or (parsed.hostname or "") != "i.ytimg.com": return url
    return parsed._replace(path=f"{match.group(1)}mqdefault{match.group(2)}", query="").geturl()


class ImageCache:
    def __init__(self, directory: Path, client: HttpClient, max_bytes: int = 256 * 1024 * 1024, concurrency: int = 8) -> None:
        self.directory = directory
        self.client = client
        self.max_bytes = max_bytes
        self._inflight: dict[str, asyncio.Task[tuple[Path, str]]] = {}
        self._limit = asyncio.Semaphore(concurrency)
        self._writes = 0
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)

    def _path(self, url: str) -> Path:
        return self.directory / hashlib.sha256(url.encode()).hexdigest()

    @staticmethod
    def _type(path: Path) -> str:
        head = path.read_bytes()[:12]
        if head.startswith(b"\x89PNG"): return "image/png"
        if head.startswith(b"RIFF") and head[8:12] == b"WEBP": return "image/webp"
        if head[:3] == b"GIF": return "image/gif"
        return "image/jpeg"

    async def get(self, url: str, width: int = 0) -> tuple[Path, str]:
        if not allowed_image_url(url): raise ValueError("Хост изображения не разрешён")
        target = downsized(url, width)
        path = self._path(target)
        if path.exists() and path.stat().st_size > 0:
            os.utime(path)
            return path, self._type(path)
        task = self._inflight.get(target)
        if task is None:
            task = asyncio.ensure_future(self._download(target, url, path))
            self._inflight[target] = task
            task.add_done_callback(lambda _: self._inflight.pop(target, None))
        return await asyncio.shield(task)

    async def _download(self, target: str, original: str, path: Path) -> tuple[Path, str]:
        async with self._limit:
            reply = await asyncio.to_thread(self.client.get, target, 8.0, None, MAX_IMAGE)
            if reply.status == 404 and target != original:
                reply = await asyncio.to_thread(self.client.get, original, 8.0, None, MAX_IMAGE)
            if reply.status != 200 or not reply.body: raise OSError(f"HTTP {reply.status}")
            if not reply.headers.get("content-type", "").startswith("image/"): raise ValueError("Не изображение")
            temporary = path.with_suffix(".tmp")
            temporary.write_bytes(reply.body)
            os.replace(temporary, path)
        self._writes += 1
        if self._writes % 40 == 0: await asyncio.to_thread(self.evict)
        return path, self._type(path)

    def evict(self) -> None:
        files = []
        for entry in self.directory.iterdir():
            try: stat = entry.stat()
            except OSError: continue
            files.append((stat.st_mtime, stat.st_size, entry))
        total = sum(size for _, size, _ in files)
        if total <= self.max_bytes: return
        for _, size, entry in sorted(files):
            entry.unlink(missing_ok=True)
            total -= size
            if total <= self.max_bytes * 0.9: break


class ImageServer:
    """Loopback HTTP endpoint so QML Image items can load cached, proxied thumbnails."""

    def __init__(self, cache: ImageCache, port: int = DEFAULT_IMAGE_PORT) -> None:
        self.cache = cache
        self.port = port
        self.server: asyncio.AbstractServer | None = None

    async def start(self) -> int:
        try:
            self.server = await asyncio.start_server(self._handle, "127.0.0.1", self.port)
        except OSError:
            self.server = await asyncio.start_server(self._handle, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]
        return self.port

    async def stop(self) -> None:
        if self.server:
            self.server.close()
            await self.server.wait_closed()

    @staticmethod
    async def _respond(writer: asyncio.StreamWriter, status: str, body: bytes = b"", content_type: str = "text/plain") -> None:
        writer.write((f"HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {len(body)}\r\n"
                      "Cache-Control: max-age=86400\r\nConnection: close\r\n\r\n").encode() + body)
        await writer.drain()

    async def _handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            line = await asyncio.wait_for(reader.readline(), 5)
            parts = line.decode("latin-1").split()
            while (await asyncio.wait_for(reader.readline(), 5)) not in (b"\r\n", b"\n", b""): pass
            if len(parts) < 2 or parts[0] != "GET":
                return await self._respond(writer, "405 Method Not Allowed")
            parsed = urlparse(parts[1])
            query = parse_qs(parsed.query)
            if parsed.path != "/img" or "u" not in query:
                return await self._respond(writer, "404 Not Found")
            try: width = int(query.get("w", ["0"])[0])
            except ValueError: width = 0
            try:
                path, content_type = await asyncio.wait_for(self.cache.get(query["u"][0], width), 20)
            except (ValueError,):
                return await self._respond(writer, "403 Forbidden")
            except (OSError, TimeoutError, asyncio.TimeoutError):
                return await self._respond(writer, "502 Bad Gateway")
            await self._respond(writer, "200 OK", await asyncio.to_thread(path.read_bytes), content_type)
        except (ConnectionError, asyncio.TimeoutError, TimeoutError):
            pass
        finally:
            try: writer.close()
            except Exception: pass
