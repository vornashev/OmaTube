from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Awaitable, Callable

from .errors import OmaTubeError
from .resolver import ResolvedMedia, ResolvedStream

MAX_RESPONSE = 1024 * 1024
EventCallback = Callable[[dict[str, Any]], Awaitable[None]]
LOGGER = logging.getLogger(__name__)
APP_ID = "org.omarchy.omatube"


class MpvController:
    def __init__(
        self,
        socket_path: Path,
        on_event: EventCallback,
        proxy: str | None = None,
    ) -> None:
        self.socket_path = socket_path
        self.on_event = on_event
        self.proxy = proxy
        self.process: asyncio.subprocess.Process | None = None
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.reader_task: asyncio.Task[None] | None = None
        self.event_task: asyncio.Task[None] | None = None
        self.event_queue: asyncio.Queue[dict[str, Any]] | None = None
        self.pending: dict[
            int,
            tuple[asyncio.StreamReader, asyncio.Future[Any]],
        ] = {}
        self.request_id = 0
        self.lifecycle_lock = asyncio.Lock()
        self._unhealthy_reader: asyncio.StreamReader | None = None
        self._closing_queues: set[asyncio.Queue[dict[str, Any]]] = set()
        self.playback_lock = asyncio.Lock()
        self.loaded: ResolvedMedia | None = None
        self.video_added = False
        self.video_mode = "audio"
        self._file_ready: asyncio.Future[None] | None = None
        self._video_close_serial = 0

    def _healthy(self) -> bool:
        return bool(
            self.process
            and self.process.returncode is None
            and self.reader
            and self.reader is not self._unhealthy_reader
            and self.writer
            and not self.writer.is_closing()
            and self.reader_task
            and not self.reader_task.done()
            and self.event_task
            and not self.event_task.done()
            and self.event_queue
        )

    def _fail_pending(
        self,
        reader: asyncio.StreamReader,
        error: OmaTubeError,
    ) -> None:
        for request_id, (pending_reader, future) in list(self.pending.items()):
            if pending_reader is not reader:
                continue
            self.pending.pop(request_id, None)
            if not future.done():
                future.set_exception(error)

    @staticmethod
    def _terminate(process: asyncio.subprocess.Process) -> None:
        if process.returncode is not None:
            return
        try:
            process.terminate()
        except ProcessLookupError:
            pass

    async def _dispose_process(
        self,
        process: asyncio.subprocess.Process | None,
        writer: asyncio.StreamWriter | None,
    ) -> None:
        if writer:
            writer.close()
            try:
                await writer.wait_closed()
            except (ConnectionError, OSError):
                pass
        if process:
            self._terminate(process)
            if process.returncode is None:
                try:
                    await asyncio.wait_for(process.wait(), 3)
                except TimeoutError:
                    try:
                        process.kill()
                    except ProcessLookupError:
                        pass
                    await process.wait()

    async def _stop_locked(self) -> None:
        process = self.process
        reader = self.reader
        writer = self.writer
        reader_task = self.reader_task
        event_task = self.event_task
        queue = self.event_queue
        if queue:
            self._closing_queues.add(queue)
        self.process = None
        self.reader = None
        self.writer = None
        self.reader_task = None
        self.event_task = None
        self.event_queue = None
        self._unhealthy_reader = None
        self.loaded = None
        self.video_added = False
        self.video_mode = "audio"
        if self._file_ready and not self._file_ready.done():
            self._file_ready.set_exception(OmaTubeError("mpv_disconnected", "Связь с mpv потеряна"))

        current_task = asyncio.current_task()
        tasks = [
            task
            for task in (reader_task, event_task)
            if task and task is not current_task
        ]
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        if reader:
            self._fail_pending(
                reader,
                OmaTubeError("playback_error", "Связь с mpv потеряна"),
            )
        await self._dispose_process(process, writer)
        if queue:
            self._closing_queues.discard(queue)
        self.socket_path.unlink(missing_ok=True)

    async def _start_locked(self) -> None:
        if self._healthy():
            return
        if (
            self.process
            or self.writer
            or self.reader_task
            or self.event_task
            or self.event_queue
        ):
            await self._stop_locked()
        self.socket_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.socket_path.unlink(missing_ok=True)
        argv = [
            "mpv",
            "--idle=yes",
            "--no-config",
            "--vid=no",
            "--vo=gpu-next",
            "--gpu-context=wayland",
            "--ao=pipewire",
            f"--wayland-app-id={APP_ID}",
            "--title=OmaTube",
            "--osc=no",
            "--osd-level=0",
            "--input-default-bindings=no",
            "--ytdl=no",
            "--audio-display=no",
            "--no-terminal",
            "--load-scripts=no",
            f"--script={Path(__file__).with_name('video_loader.lua')}",
            "--force-window=no",
            "--audio-client-name=OmaTube",
            f"--input-ipc-server={self.socket_path}",
        ]
        if self.proxy:
            argv.append(f"--http-proxy={self.proxy}")
        try:
            process = await asyncio.create_subprocess_exec(
                *argv,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
        except FileNotFoundError as exc:
            raise OmaTubeError("dependency_missing", "Не найден mpv") from exc

        reader: asyncio.StreamReader | None = None
        writer: asyncio.StreamWriter | None = None
        try:
            for _ in range(100):
                if process.returncode is not None:
                    raise OmaTubeError(
                        "playback_error",
                        "mpv завершился при запуске",
                    )
                try:
                    reader, writer = await asyncio.open_unix_connection(
                        self.socket_path
                    )
                    break
                except (FileNotFoundError, ConnectionRefusedError):
                    await asyncio.sleep(0.05)
            else:
                raise OmaTubeError(
                    "playback_error",
                    "mpv не создал управляющий сокет",
                )
            self.socket_path.chmod(0o600)
            queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
            self.process = process
            self.reader = reader
            self.writer = writer
            self.event_queue = queue
            self._unhealthy_reader = None
            self.reader_task = asyncio.create_task(
                self._read_loop(reader, queue)
            )
            self.event_task = asyncio.create_task(self._event_loop(queue))
            for property_name in (
                "pause",
                "time-pos",
                "duration",
                "seekable",
                "idle-active",
                "volume",
                "mute",
                "seeking",
                "paused-for-cache",
                "core-idle",
            ):
                await self._command_connected(
                    ["observe_property", 0, property_name]
                )
            await self._command_connected([
                "keybind", "CLOSE_WIN", "set vid no; script-message omatube-video-closed",
            ])
        except BaseException:
            if self.process is process:
                await self._stop_locked()
            else:
                await self._dispose_process(process, writer)
                self.socket_path.unlink(missing_ok=True)
            raise

    async def start(self) -> None:
        async with self.lifecycle_lock:
            await self._start_locked()

    async def _read_loop(
        self,
        reader: asyncio.StreamReader,
        event_queue: asyncio.Queue[dict[str, Any]],
    ) -> None:
        try:
            while line := await reader.readline():
                if len(line) > MAX_RESPONSE:
                    raise OmaTubeError(
                        "playback_error",
                        "Ответ mpv слишком велик",
                    )
                try:
                    payload = json.loads(line)
                except json.JSONDecodeError:
                    continue
                request_id = payload.get("request_id")
                pending = self.pending.get(request_id)
                if pending and pending[0] is reader:
                    self.pending.pop(request_id, None)
                    future = pending[1]
                    if future.done():
                        continue
                    if payload.get("error") == "success":
                        future.set_result(payload.get("data"))
                    else:
                        future.set_exception(OmaTubeError(
                            "playback_error",
                            f"mpv отклонил команду: {payload.get('error', 'unknown error')}",
                        ))
                elif payload.get("event"):
                    if payload.get("event") == "client-message" and payload.get("args") == ["omatube-video-closed"]:
                        self._video_close_serial += 1
                    if self._file_ready and not self._file_ready.done():
                        if payload["event"] == "file-loaded":
                            self._file_ready.set_result(None)
                        elif payload["event"] == "end-file" and payload.get("reason") == "error":
                            self._file_ready.set_exception(OmaTubeError("playback_error", "Не удалось открыть медиапоток"))
                    event_queue.put_nowait(payload)
        finally:
            if self.reader is reader:
                self._unhealthy_reader = reader
                if self._file_ready and not self._file_ready.done():
                    self._file_ready.set_exception(OmaTubeError("mpv_disconnected", "Связь с mpv потеряна"))
            self._fail_pending(
                reader,
                OmaTubeError("playback_error", "Связь с mpv потеряна"),
            )
            if event_queue not in self._closing_queues:
                event_queue.put_nowait({"event": "omatube-disconnected"})

    async def _event_loop(
        self,
        queue: asyncio.Queue[dict[str, Any]],
    ) -> None:
        while True:
            event = await queue.get()
            try:
                if queue is not self.event_queue:
                    return
                await self.on_event(event)
            except asyncio.CancelledError:
                raise
            except Exception:
                LOGGER.exception("Unhandled mpv event callback")
            finally:
                queue.task_done()
            if queue is not self.event_queue:
                return

    async def _command_connected(self, command: list[Any]) -> Any:
        assert self.reader and self.writer
        reader = self.reader
        writer = self.writer
        self.request_id += 1
        request_id = self.request_id
        future = asyncio.get_running_loop().create_future()
        self.pending[request_id] = (reader, future)
        payload = json.dumps(
            {"command": command, "request_id": request_id},
            separators=(",", ":"),
        )
        try:
            writer.write((payload + "\n").encode())
            await writer.drain()
            return await asyncio.wait_for(future, 45 if command[0] == "video-add" else 5)
        except TimeoutError as exc:
            if self.reader is reader:
                self._unhealthy_reader = reader
            writer.close()
            raise OmaTubeError(
                "playback_error",
                "mpv не ответил на команду",
            ) from exc
        except (ConnectionError, OSError, RuntimeError) as exc:
            if self.reader is reader:
                self._unhealthy_reader = reader
            raise OmaTubeError(
                "playback_error",
                "Не удалось отправить команду mpv",
            ) from exc
        finally:
            pending = self.pending.get(request_id)
            if pending and pending[1] is future:
                self.pending.pop(request_id, None)
            if not future.done():
                future.cancel()

    async def command(self, command: list[Any]) -> Any:
        async with self.lifecycle_lock:
            await self._start_locked()
            return await self._command_connected(command)

    async def _stream_options(self, stream: ResolvedStream) -> None:
        await self.command(["set_property", "http-header-fields", [f"{key}: {value}" for key, value in stream.headers.items()]])
        await self.command(["set_property", "http-proxy", stream.proxy or ""])

    async def set_video_loading(self, visible: bool, token: str = "mode") -> None:
        if not self._healthy():
            return
        await self.command([
            "script-message", "omatube-loader", "show" if visible else "hide", token,
        ])

    async def load(self, media: ResolvedMedia, start: float = 0.0, paused: bool = False) -> None:
        async with self.playback_lock:
            self.loaded = None
            self.video_added = False
            await self.command(["set_property", "vid", "no"])
            await self._stream_options(media.audio)
            await self.command(["set_property", "pause", paused])
            ready = asyncio.get_running_loop().create_future()
            self._file_ready = ready
            try:
                await self.command(["loadfile", media.audio.url, "replace", -1, {"start": str(max(0.0, start))}])
                await asyncio.wait_for(ready, 45)
                self.loaded = media
            except (asyncio.CancelledError, TimeoutError):
                await self.command(["stop"])
                raise
            finally:
                self._file_ready = None
                if not ready.done():
                    ready.cancel()

    async def _hyprctl(self, *args: str) -> str:
        try:
            process = await asyncio.create_subprocess_exec(
                "hyprctl", *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
            )
        except FileNotFoundError as exc:
            raise OmaTubeError("video_error", "Не найден hyprctl") from exc
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), 3)
        except (asyncio.CancelledError, TimeoutError) as error:
            self._terminate(process)
            await process.wait()
            if isinstance(error, TimeoutError):
                raise OmaTubeError("video_error", "Hyprland не ответил") from error
            raise
        output = stdout.decode("utf-8", "replace").strip()
        if process.returncode or (args[0] == "dispatch" and output != "ok"):
            raise OmaTubeError("video_error", "Hyprland не применил режим окна OmaTube")
        return output

    async def _video_window(self) -> dict[str, Any] | None:
        try:
            clients = json.loads(await self._hyprctl("clients", "-j"))
            if not isinstance(clients, list) or any(not isinstance(row, dict) for row in clients):
                raise TypeError
        except (json.JSONDecodeError, TypeError) as exc:
            raise OmaTubeError("video_error", "Hyprland вернул некорректный список окон") from exc
        pid = self.process.pid if self.process else None
        return next((row for row in clients
                     if row.get("pid") == pid and row.get("class") == APP_ID
                     and row.get("mapped") and isinstance(row.get("address"), str)), None)

    async def _place_video(self, mode: str) -> None:
        for _ in range(60):
            window = await self._video_window()
            if window:
                break
            if await self.command(["get_property", "vid"]) == "no":
                raise OmaTubeError("video_error", "mpv не включил видеопоток")
            await asyncio.sleep(0.05)
        else:
            raise OmaTubeError("video_error", "Окно видео OmaTube не появилось")
        address = window["address"]
        if not address.startswith("0x") or any(char not in "0123456789abcdefABCDEF" for char in address[2:]):
            raise OmaTubeError("video_error", "Hyprland вернул некорректный адрес окна")
        target = f'window = "address:{address}"'

        async def dispatch(operation: str, arguments: str = "") -> None:
            # Re-identify by PID and app-id before every mutation: vid=no destroys
            # the surface, and re-enabling video gives it a different address.
            current = await self._video_window()
            if not current or current["address"] != address:
                raise OmaTubeError("video_error", "Окно видео OmaTube исчезло")
            await self._hyprctl("dispatch", f"hl.dsp.window.{operation}({{ {target}{arguments} }})")

        floating = mode == "floating"
        if window.get("pinned") and not floating:
            await dispatch("pin")
        if bool(window.get("floating")) != floating:
            await dispatch("float", ', action = "toggle"')
        if floating:
            await dispatch("resize", ", x = 960, y = 540")
            await dispatch("center")
            if not window.get("pinned"):
                await dispatch("pin")
            await dispatch("alter_zorder", ', mode = "top"')

    async def set_video_mode(self, mode: str) -> None:
        async with self.playback_lock:
            if mode == "audio":
                if self.writer:
                    await self.command(["set_property", "vid", "no"])
                    await self.command(["set_property", "force-window", False])
                self.video_mode = mode
                return
            media = self.loaded
            if not media or not media.video:
                raise OmaTubeError("video_unavailable", "Видеопоток отсутствует")
            close_serial = self._video_close_serial
            await self.command(["set_property", "force-window", True])
            await self.set_video_loading(True)
            try:
                if media.video.url != media.audio.url and not self.video_added:
                    await self._stream_options(media.video)
                    try:
                        await self.command(["video-add", media.video.url, "select"])
                        self.video_added = True
                    finally:
                        await self._stream_options(media.audio)
                else:
                    await self.command(["set_property", "vid", "auto"])
                await self._place_video(mode)
            except BaseException as error:
                if self._healthy():
                    await self.command(["set_property", "vid", "no"])
                    await self.command(["set_property", "force-window", False])
                self.video_mode = "audio"
                if isinstance(error, OmaTubeError) and close_serial != self._video_close_serial:
                    raise OmaTubeError("video_closed", "Окно видео закрыто") from error
                raise
            finally:
                try:
                    await self.set_video_loading(False)
                except OmaTubeError:
                    pass
            self.video_mode = mode

    async def pause(self, paused: bool) -> None:
        await self.command(["set_property", "pause", paused])

    async def seek(self, seconds: float) -> None:
        await self.command(["seek", max(0.0, seconds), "absolute", "exact"])

    async def set_volume(self, value: float) -> None:
        await self.command([
            "set_property",
            "volume",
            max(0.0, min(100.0, value)),
        ])

    async def set_mute(self, value: bool) -> None:
        await self.command(["set_property", "mute", value])

    async def stop_playback(self, preserve_window: bool = False) -> None:
        async with self.playback_lock:
            if self.writer:
                await self.command(["set_property", "force-window", preserve_window])
                await self.command(["stop"])
            self.loaded = None
            self.video_added = False
            if not preserve_window:
                self.video_mode = "audio"

    async def stop(self) -> None:
        async with self.lifecycle_lock:
            await self._stop_locked()
