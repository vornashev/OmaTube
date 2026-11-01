from __future__ import annotations

import asyncio
import os
import re
import shutil
import signal
import time
from pathlib import Path
from typing import Any, Callable
from uuid import uuid4

from .auth import secure_cookie_file
from .errors import OmaTubeError
from .urls import canonical_video_url

PROGRESS = re.compile(r"^download:(\d+|NA)/(\d+|NA)/(\d+|NA)/([\d.]+|NA)/([\d.]+|NA)$")
KINDS = frozenset({"audio", "video"})
MAX_PARALLEL = 2


def parse_progress(line: str) -> dict[str, Any] | None:
    match = PROGRESS.match(line.strip())
    if not match: return None
    downloaded, total, estimate, speed, eta = match.groups()
    number = lambda value, cast: None if value == "NA" else cast(value)
    return {"downloaded": number(downloaded, int) or 0, "total": number(total, int) or number(estimate, int),
            "speed": number(speed, float), "eta": number(eta, float)}


def explain_failure(stderr: str) -> str:
    text = stderr.lower()
    if "403" in text: return "HTTP 403 — нужен вход в аккаунт или обновите yt-dlp"
    if "sign in" in text or "confirm you" in text: return "Нужен вход в аккаунт YouTube"
    if "not available" in text or "private video" in text: return "Видео недоступно"
    if "no space" in text: return "Нет места на диске"
    if "ffmpeg" in text and "not found" in text: return "Не найден ffmpeg"
    last = [line for line in stderr.strip().splitlines() if line.strip()]
    return (last[-1][:160] if last else "Не удалось скачать")


class DownloadManager:
    def __init__(self, storage, directory: Path, python: str | Path, cookies_path: Path | None, proxy: str | None,
                 changed: Callable[[], None], command_factory: Callable[[dict[str, Any]], list[str]] | None = None,
                 quality: Callable[[], int] | None = None) -> None:
        self.storage = storage
        self.directory = directory
        self.python = str(python)
        self.cookies_path = cookies_path
        self.proxy = proxy
        self.changed = changed
        self.quality = quality or (lambda: 1080)
        self._command_factory = command_factory
        self.processes: dict[str, asyncio.subprocess.Process] = {}
        self.tasks: dict[str, asyncio.Task[None]] = {}
        self.paused: set[str] = set()
        self.cancelled: set[str] = set()
        storage.interrupt_downloads()

    def argv(self, item: dict[str, Any]) -> list[str]:
        if self._command_factory: return self._command_factory(item)
        template = str(self.directory / "%(title).150B [%(id)s].%(ext)s")
        argv = [self.python, "-m", "yt_dlp", "--ignore-config", "--no-playlist", "--js-runtimes", "deno", "--continue", "--extractor-args", "youtube:skip=hls", "--socket-timeout", "10", "--retries", "10", "--extractor-retries", "6",
                "--newline", "--progress-template", "download:%(progress.downloaded_bytes)s/%(progress.total_bytes)s/%(progress.total_bytes_estimate)s/%(progress.speed)s/%(progress.eta)s",
                "--print", "after_move:filepath", "-o", template]
        if item["kind"] == "audio":
            argv += ["-f", "bestaudio", "-x", "--audio-format", "opus"]
        else:
            height = self.quality()
            argv += ["-f", f"bestvideo[height<={height}]+bestaudio/best[height<={height}]", "--merge-output-format", "mp4"]
        if self.cookies_path and secure_cookie_file(self.cookies_path): argv += ["--cookies", str(self.cookies_path)]
        if self.proxy: argv += ["--proxy", self.proxy]
        return [*argv, "--", canonical_video_url(item["videoId"])]

    def add(self, media: dict[str, Any], kind: str) -> dict[str, Any]:
        if kind not in KINDS: raise OmaTubeError("invalid_request", "Неизвестный формат загрузки")
        video_id = media.get("videoId")
        if not isinstance(video_id, str) or not video_id: raise OmaTubeError("invalid_request", "У медиа отсутствует videoId")
        existing = next((row for row in self.storage.downloads() if row["videoId"] == video_id and row["kind"] == kind
                         and row["state"] in {"queued", "running", "paused"}), None)
        if existing: return existing
        self.directory.mkdir(parents=True, exist_ok=True)
        download_id = str(uuid4())
        self.storage.create_download(download_id, media, kind)
        self._pump(); self.changed()
        return self.storage.download(download_id)

    def _pump(self) -> None:
        for row in reversed(self.storage.downloads()):
            if row["state"] != "queued" or row["id"] in self.tasks: continue
            if len(self.tasks) >= MAX_PARALLEL: break
            self.tasks[row["id"]] = asyncio.ensure_future(self._run(row))

    async def _run(self, item: dict[str, Any]) -> None:
        download_id = item["id"]
        self.storage.update_download(download_id, state="running", error=None); self.changed()
        stderr_tail = ""
        try:
            process = await asyncio.create_subprocess_exec(*self.argv(item), stdout=asyncio.subprocess.PIPE,
                                                            stderr=asyncio.subprocess.PIPE, start_new_session=True)
            self.processes[download_id] = process
            stderr_task = asyncio.ensure_future(process.stderr.read(65536))
            filepath = None; last_write = 0.0
            async for raw in process.stdout:
                line = raw.decode("utf-8", "replace").strip()
                progress = parse_progress(line)
                if progress:
                    if time.monotonic() - last_write >= 0.4:
                        self.storage.update_download(download_id, **progress); self.changed(); last_write = time.monotonic()
                elif line.startswith("/"):
                    filepath = line
            code = await process.wait()
            stderr_tail = (await stderr_task).decode("utf-8", "replace")
            if download_id in self.cancelled:
                return
            if code == 0:
                size = None
                if filepath and os.path.exists(filepath): size = os.path.getsize(filepath)
                self.storage.update_download(download_id, state="done", filepath=filepath, size=size, speed=None, eta=None,
                                             downloaded=size or 0, total=size, finished_at=time.time())
            else:
                self.storage.update_download(download_id, state="failed", error=explain_failure(stderr_tail), speed=None, eta=None, finished_at=time.time())
        except asyncio.CancelledError:
            raise
        except (OSError, FileNotFoundError):
            self.storage.update_download(download_id, state="failed", error="Не удалось запустить yt-dlp", finished_at=time.time())
        finally:
            self.processes.pop(download_id, None); self.tasks.pop(download_id, None); self.paused.discard(download_id)
            self.changed()
            self._pump()

    def _signal(self, download_id: str, sig: int) -> bool:
        process = self.processes.get(download_id)
        if not process or process.returncode is not None: return False
        try: os.killpg(process.pid, sig)
        except ProcessLookupError: return False
        return True

    def pause(self, download_id: str) -> None:
        if self._signal(download_id, signal.SIGSTOP):
            self.paused.add(download_id)
            self.storage.update_download(download_id, state="paused", speed=None, eta=None); self.changed()

    def resume(self, download_id: str) -> None:
        if download_id in self.paused and self._signal(download_id, signal.SIGCONT):
            self.paused.discard(download_id); self.storage.update_download(download_id, state="running"); self.changed()

    def pause_all(self) -> None:
        for row in self.storage.downloads():
            if row["state"] == "running": self.pause(row["id"])

    def resume_all(self) -> None:
        for download_id in list(self.paused): self.resume(download_id)

    async def cancel(self, download_id: str) -> None:
        self.cancelled.add(download_id)
        if download_id in self.paused: self._signal(download_id, signal.SIGCONT)
        self._signal(download_id, signal.SIGKILL)
        task = self.tasks.get(download_id)
        if task: await asyncio.gather(task, return_exceptions=True)
        self.cancelled.discard(download_id)
        self.storage.delete_download(download_id); self.changed()

    def retry(self, download_id: str) -> None:
        row = self.storage.download(download_id)
        if row and row["state"] == "failed":
            self.storage.update_download(download_id, state="queued", error=None, finished_at=None); self._pump(); self.changed()

    async def remove(self, download_id: str, delete_file: bool = False) -> None:
        row = self.storage.download(download_id)
        if not row: return
        if row["state"] in {"queued", "running", "paused"}:
            await self.cancel(download_id); return
        if delete_file and row["filepath"]:
            path = Path(row["filepath"])
            if self.directory in path.parents:
                try: path.unlink()
                except OSError: pass
        self.storage.delete_download(download_id); self.changed()

    def active_count(self) -> int:
        return sum(1 for row in self.storage.downloads() if row["state"] in {"queued", "running", "paused"})

    def summary(self) -> dict[str, Any]:
        rows = self.storage.downloads()
        used = sum(row["size"] or 0 for row in rows if row["state"] == "done")
        try: free = shutil.disk_usage(self.directory if self.directory.exists() else self.directory.parent).free
        except OSError: free = None
        return {"items": rows, "directory": str(self.directory), "used": used, "free": free,
                "active": sum(1 for row in rows if row["state"] in {"queued", "running", "paused"})}

    async def shutdown(self) -> None:
        for download_id in list(self.processes):
            self.cancelled.add(download_id)
            if download_id in self.paused: self._signal(download_id, signal.SIGCONT)
            self._signal(download_id, signal.SIGTERM)
        if self.tasks: await asyncio.gather(*self.tasks.values(), return_exceptions=True)
        self.storage.interrupt_downloads()
