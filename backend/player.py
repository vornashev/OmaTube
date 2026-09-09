from __future__ import annotations

import asyncio
import logging
import random
import time
from typing import Any, Callable
from uuid import uuid4

from .errors import OmaTubeError
from .mpv import MpvController
from .resolver import MediaResolver
from .storage import Storage
LOGGER = logging.getLogger(__name__)


class Player:
    def __init__(
        self,
        storage: Storage,
        resolver: MediaResolver,
        mpv: MpvController,
        changed: Callable[[], None],
        collection_changed: Callable[[], None] | None = None,
    ) -> None:
        self.storage = storage
        self.resolver = resolver
        self.mpv = mpv
        self.changed = changed
        self.collection_changed = collection_changed
        self.queue: list[dict[str, Any]] = []
        self.current_id: str | None = None
        self.state = "idle"; self.position = 0.0; self.duration: float | None = None; self.can_seek = False
        self.volume = 100.0; self.muted = False; self.shuffle = False; self.repeat = "off"
        self.error: dict[str, str] | None = None
        self.queue_revision = 0; self.generation = 0
        self.shuffle_order: list[str] = []; self.played: list[str] = []
        self.resolve_task: asyncio.Task[None] | None = None
        self.history_timer: asyncio.Task[None] | None = None
        self.buffering = False
        self._seeking = False
        self._paused_for_cache = False
        self._core_idle = False
        self._mpv_paused = True
        self._buffering_clear_task: asyncio.Task[None] | None = None
        self.history_enabled = True; self._history_generation = -1
        self._last_position_save = 0.0; self._transition_lock = asyncio.Lock(); self._eof_generation = -1
        self._retried_entry_id: str | None = None
        self.video_mode = "audio"
        self._mode_lock = asyncio.Lock()
        self._loaded_generation = -1
        self._desired_paused = False
        self._restore()

    def _restore(self) -> None:
        try: snapshot = self.storage.load_player_state()
        except OmaTubeError as error:
            self.error = error.as_dict(); return
        if not snapshot: return
        try:
            queue = snapshot.get("queue", [])
            if not isinstance(queue, list) or any(not isinstance(row.get("entryId"), str) or not isinstance(row.get("media"), dict) for row in queue):
                raise ValueError
            self.queue = queue; ids = {row["entryId"] for row in queue}
            self.current_id = snapshot.get("currentEntryId") if snapshot.get("currentEntryId") in ids else None
            self.position = max(0.0, float(snapshot.get("position", 0)))
            self.volume = max(0.0, min(100.0, float(snapshot.get("volume", 100))))
            self.muted = bool(snapshot.get("muted", False)); self.shuffle = bool(snapshot.get("shuffle", False))
            self.repeat = snapshot.get("repeat") if snapshot.get("repeat") in {"off", "one", "all"} else "off"
            mode = snapshot.get("videoMode", "audio")
            self.video_mode = mode if mode in {"audio", "tile", "floating"} else "audio"
            self.shuffle_order = [item for item in snapshot.get("shuffleOrder", []) if item in ids]
            self.played = [item for item in snapshot.get("played", []) if item in ids]
            self.state = "paused" if self.current_id else "idle"
        except (TypeError, ValueError, AttributeError):
            self.queue = []; self.current_id = None; self.state = "idle"
            self.error = {"code": "storage_error", "message": "Сохранённое состояние плеера повреждено"}

    @property
    def current(self) -> dict[str, Any] | None:
        return next((row for row in self.queue if row["entryId"] == self.current_id), None)

    def snapshot(self) -> dict[str, Any]:
        return {"queue": self.queue, "currentEntryId": self.current_id, "position": self.position,
                "volume": self.volume, "muted": self.muted, "shuffle": self.shuffle,
                "shuffleOrder": self.shuffle_order, "played": self.played, "repeat": self.repeat,
                "videoMode": self.video_mode}

    def persist(self, force: bool = True) -> None:
        now = time.monotonic()
        if force or now - self._last_position_save >= 5:
            self.storage.save_player_state(self.snapshot()); self._last_position_save = now

    def status(self) -> dict[str, Any]:
        return {"state": self.state, "current": self.current, "position": self.position,
                "duration": self.duration, "volume": self.volume, "muted": self.muted,
                "shuffle": self.shuffle, "repeat": self.repeat, "canSeek": self.can_seek,
                "queueRevision": self.queue_revision, "error": self.error, "videoMode": self.video_mode,
                "buffering": self.buffering}


    def _update_buffering(self) -> None:
        active = self._seeking or self._paused_for_cache or (self._core_idle and not self._mpv_paused)
        if active:
            if self._buffering_clear_task:
                self._buffering_clear_task.cancel()
                self._buffering_clear_task = None
            if not self.buffering:
                self.buffering = True
                self.changed()
            return
        if not self.buffering or self._buffering_clear_task:
            return

        async def clear_after_resume() -> None:
            try:
                await asyncio.sleep(0.25)
                if not (self._seeking or self._paused_for_cache or (self._core_idle and not self._mpv_paused)):
                    self.buffering = False
                    self.changed()
            finally:
                self._buffering_clear_task = None

        self._buffering_clear_task = asyncio.create_task(clear_after_resume())

    def _reset_buffering(self) -> None:
        if self._buffering_clear_task:
            self._buffering_clear_task.cancel()
            self._buffering_clear_task = None
        self._seeking = False
        self._paused_for_cache = False
        self._core_idle = False
        self._mpv_paused = self._desired_paused
        self.buffering = False

    def _entry(self, media: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(media, dict) or not isinstance(media.get("videoId"), str):
            raise OmaTubeError("invalid_request", "У медиа отсутствует videoId")
        return {"entryId": str(uuid4()), "media": media.copy()}

    async def replace_many(self, media: list[dict[str, Any]]) -> dict[str, Any]:
        entries = [self._entry(item) for item in media]
        if not entries:
            raise OmaTubeError("not_found", "Очередь пуста")
        self.queue = entries
        self.current_id = entries[0]["entryId"]
        self.shuffle_order = []
        self.played = []
        self.queue_revision += 1
        self.persist()
        await self._load_current(0)
        return entries[0]

    async def replace(self, media: dict[str, Any]) -> dict[str, Any]:
        return await self.replace_many([media])

    def enqueue(self, media: dict[str, Any], placement: str) -> dict[str, Any]:
        entry = self._entry(media)
        if placement == "next" and self.current_id:
            index = next(index for index, row in enumerate(self.queue) if row["entryId"] == self.current_id)
            self.queue.insert(index + 1, entry)
        elif placement == "end": self.queue.append(entry)
        else: raise OmaTubeError("invalid_request", "Неизвестное место в очереди")
        if self.shuffle:
            if placement == "next" and self.current_id in self.shuffle_order:
                self.shuffle_order.insert(self.shuffle_order.index(self.current_id) + 1, entry["entryId"])
            else:
                self.shuffle_order.append(entry["entryId"])
        self.queue_revision += 1; self.persist(); self.changed(); return entry

    async def _load_current(self, start: float = 0.0, retry: bool = True) -> None:
        current = self.current
        if retry: self._retried_entry_id = None
        if not current: self.state = "idle"; self.changed(); return
        self.generation += 1; generation = self.generation; self._eof_generation = -1
        self._loaded_generation = -1
        if retry: self._desired_paused = False
        if self.resolve_task: self.resolve_task.cancel()
        if self.history_timer: self.history_timer.cancel()
        self._reset_buffering()
        self.state = "loading"; self.error = None; self.position = start
        self.duration = None; self.can_seek = False; self.changed()
        async def resolve_and_load() -> None:
            loader_token = f"load-{generation}"
            loader_visible = False
            try:
                if self.mpv.writer:
                    await self.mpv.stop_playback(preserve_window=self.video_mode != "audio")
                    if self.video_mode != "audio":
                        await self.mpv.set_video_loading(True, loader_token)
                        loader_visible = True
                if generation != self.generation: return
                audio = await self.resolver.resolve(current["media"]["videoId"])
                if generation != self.generation or self.current_id != current["entryId"]: return
                media = current["media"]
                resolved_metadata = {
                    "title": audio.title, "author": audio.author,
                    "thumbnailUrl": audio.thumbnail_url, "canonicalUrl": audio.canonical_url,
                    "viewCount": audio.view_count, "likeCount": audio.like_count,
                }
                changed_metadata = False
                for key, value in resolved_metadata.items():
                    if value is not None and value != "" and media.get(key) != value:
                        media[key] = value; changed_metadata = True
                if changed_metadata:
                    self.queue_revision += 1; self.persist()
                self.duration = audio.duration; self.can_seek = audio.seekable
                await self.mpv.load(audio, start if audio.seekable else 0, paused=self._desired_paused)
                if generation != self.generation: return
                self._loaded_generation = generation
                await self.mpv.set_volume(self.volume); await self.mpv.set_mute(self.muted)
                await self.mpv.pause(self._desired_paused)
                if generation != self.generation: return
                self.state = "paused" if self._desired_paused else "playing"
                async with self._mode_lock:
                    if generation != self.generation: return
                    try:
                        await self.mpv.set_video_mode(self.video_mode)
                    except OmaTubeError as error:
                        if generation != self.generation: return
                        self.video_mode = "audio"
                        if error.code != "video_closed": self.error = error.as_dict()
                    self.persist(); self.changed()
                if generation != self.generation: return
                self.history_timer = asyncio.create_task(self._history_after_delay(generation, current["media"]))
            except asyncio.CancelledError: raise
            except OmaTubeError as error:
                if generation != self.generation: return
                self.state = "error"; self.error = error.as_dict(); self.changed()
            except Exception:
                LOGGER.exception("Unexpected playback failure")
                if generation != self.generation:
                    return
                self.state = "error"
                self.error = {"code": "playback_error", "message": "Не удалось запустить воспроизведение"}
                self.changed()
            finally:
                if loader_visible:
                    try:
                        await self.mpv.set_video_loading(False, loader_token)
                    except OmaTubeError:
                        pass
        self.resolve_task = asyncio.create_task(resolve_and_load())
        await asyncio.sleep(0)

    async def _history_after_delay(self, generation: int, media: dict[str, Any]) -> None:
        await asyncio.sleep(5)
        if self.history_enabled and generation == self.generation and self.state == "playing" and self._history_generation != generation:
            self.storage.add_history(media)
            self._history_generation = generation
            if self.collection_changed:
                self.collection_changed()
            self.changed()

    def _ordered_ids(self) -> list[str]:
        if not self.shuffle: return [row["entryId"] for row in self.queue]
        ids = [row["entryId"] for row in self.queue]
        retained = [item for item in self.shuffle_order if item in ids]
        missing = [item for item in ids if item not in retained]
        random.shuffle(missing)
        self.shuffle_order = retained + missing
        return self.shuffle_order

    def _next_id(self, manual: bool = False) -> str | None:
        order = self._ordered_ids()
        if self.current_id not in order: return order[0] if order else None
        index = order.index(self.current_id)
        if index + 1 < len(order): return order[index + 1]
        if self.repeat == "all": return order[0] if order else None
        return None

    async def play(self) -> None:
        self._desired_paused = False
        if self.resolve_task and not self.resolve_task.done() and self._loaded_generation != self.generation:
            self.state = "loading"; self.changed(); return
        if not self.current_id and self.queue: self.current_id = self.queue[0]["entryId"]
        if not self.current_id: raise OmaTubeError("not_found", "Очередь пуста")
        if self.state in {"paused", "playing"} and self.mpv.writer and self._loaded_generation == self.generation:
            await self.mpv.pause(False); self.state = "playing"; self.changed(); return
        await self._load_current(self.position)

    async def pause(self) -> None:
        self._desired_paused = True
        if self.mpv.writer: await self.mpv.pause(True)
        if self.current_id: self.state = "paused"
        self.persist(); self.changed()

    async def next(self, manual: bool = True) -> None:
        async with self._transition_lock:
            target = self._next_id(manual)
            if not target:
                self.generation += 1
                self._loaded_generation = -1
                if self.resolve_task: self.resolve_task.cancel()
                self.state = "idle"; self.current_id = None; self.position = 0; self.duration = None; self.can_seek = False
                await self.mpv.stop_playback(); self.persist(); self.changed(); return
            if self.current_id: self.played.append(self.current_id)
            self.current_id = target; self.persist(); await self._load_current(0)

    async def previous(self) -> None:
        if self.position > 5 and self.current_id:
            await self.seek(0); return
        target = self.played.pop() if self.played else None
        if not target: await self.seek(0); return
        self.current_id = target; self.persist(); await self._load_current(0)

    async def seek(self, seconds: float) -> None:
        if not self.can_seek: raise OmaTubeError("invalid_request", "Перемотка недоступна")
        self._seeking = True
        self._update_buffering()
        try:
            await self.mpv.seek(seconds)
        except BaseException:
            self._seeking = False
            self._update_buffering()
            raise
        self.position = max(0.0, seconds); self.persist(); self.changed()

    async def play_entry(self, entry_id: str) -> None:
        if not any(row["entryId"] == entry_id for row in self.queue): raise OmaTubeError("not_found", "Элемент очереди не найден")
        self.current_id = entry_id; self.persist(); await self._load_current(0)

    async def remove(self, entry_id: str) -> None:
        index = next((i for i, row in enumerate(self.queue) if row["entryId"] == entry_id), -1)
        if index < 0: raise OmaTubeError("not_found", "Элемент очереди не найден")
        is_current = entry_id == self.current_id; self.queue.pop(index)
        self.shuffle_order = [item for item in self.shuffle_order if item != entry_id]
        self.played = [item for item in self.played if item != entry_id]
        self.queue_revision += 1
        if is_current:
            self.current_id = self.queue[min(index, len(self.queue)-1)]["entryId"] if self.queue else None
            if self.current_id: await self._load_current(0)
            else: await self.clear()
        self.persist(); self.changed()

    def move(self, entry_id: str, before_entry_id: str | None) -> None:
        ids = [row["entryId"] for row in self.queue]
        if entry_id not in ids or (before_entry_id is not None and before_entry_id not in ids): raise OmaTubeError("not_found", "Элемент очереди не найден")
        row = self.queue.pop(ids.index(entry_id)); ids.remove(entry_id)
        self.queue.insert(ids.index(before_entry_id) if before_entry_id else len(self.queue), row)
        self.queue_revision += 1; self.persist(); self.changed()

    async def clear(self) -> None:
        self.generation += 1
        self._loaded_generation = -1
        if self.resolve_task: self.resolve_task.cancel()
        self.queue = []; self.current_id = None; self.state = "idle"; self.position = 0; self.duration = None; self.can_seek = False
        self.queue_revision += 1
        if self.mpv.writer: await self.mpv.stop_playback()
        self.persist(); self.changed()

    def set_shuffle(self, value: bool) -> None:
        self.shuffle = value; self.shuffle_order = []
        if value:
            self.shuffle_order = [row["entryId"] for row in self.queue]; random.shuffle(self.shuffle_order)
        self.persist(); self.changed()

    def set_repeat(self, value: str) -> None:
        if value not in {"off", "one", "all"}: raise OmaTubeError("invalid_request", "Некорректный режим повтора")
        self.repeat = value; self.persist(); self.changed()

    async def reload_current(self) -> None:
        if not self.current:
            return
        self._desired_paused = self.state == "paused" or self._desired_paused
        await self._load_current(self.position, retry=False)

    async def set_video_mode(self, value: str) -> None:
        if value not in {"audio", "tile", "floating"}:
            raise OmaTubeError("invalid_request", "Некорректный режим видео")
        async with self._mode_lock:
            should_apply = self._loaded_generation == self.generation
            # A reserved surface can outlive the loaded track while the next
            # item resolves. Audio mode and CLOSE_WIN must release it at once.
            if value == "audio" and self.mpv.writer:
                should_apply = True
            if should_apply:
                try:
                    await self.mpv.set_video_mode(value)
                except OmaTubeError as error:
                    self.video_mode = "audio"
                    self.error = None if error.code == "video_closed" else error.as_dict()
                    self.persist(); self.changed()
                    if error.code != "video_closed": raise
                    return
            self.video_mode = value
            if self.error and self.error.get("code") in {"video_error", "video_unavailable"}:
                self.error = None
            self.persist(); self.changed()

    async def handle_mpv_event(self, event: dict[str, Any]) -> None:
        if event.get("event") == "client-message" and event.get("args") == ["omatube-video-closed"]:
            await self.set_video_mode("audio")
            return
        if event.get("event") == "omatube-disconnected":
            self._loaded_generation = -1
            if self.current_id:
                self.state = "error"
                self.error = {
                    "code": "mpv_disconnected",
                    "message": "Связь с mpv потеряна; нажмите «Продолжить», чтобы переподключиться",
                }
                self.persist()
                self.changed()
            return
        if event.get("event") == "property-change":
            name = event.get("name"); value = event.get("data")
            if self._loaded_generation != self.generation and name in {
                "time-pos", "duration", "seekable", "pause", "seeking", "paused-for-cache", "core-idle",
            }:
                return
            if name == "time-pos" and isinstance(value, (int, float)): self.position = float(value); self.persist(False)
            elif name == "duration" and isinstance(value, (int, float)): self.duration = float(value)
            elif name == "seekable": self.can_seek = bool(value)
            elif name == "pause" and isinstance(value, bool) and self.current_id:
                self._mpv_paused = value
                self.state = "paused" if value else "playing"
                self._update_buffering()
            elif name == "seeking":
                self._seeking = bool(value)
                self._update_buffering()
            elif name == "paused-for-cache":
                self._paused_for_cache = bool(value)
                self._update_buffering()
            elif name == "core-idle":
                self._core_idle = bool(value)
                self._update_buffering()
            elif name == "volume" and isinstance(value, (int, float)): self.volume = float(value)
            elif name == "mute" and isinstance(value, bool): self.muted = value
            self.changed()
        elif event.get("event") == "end-file":
            reason = event.get("reason")
            if self._loaded_generation != self.generation:
                return
            if reason == "eof":
                if self._eof_generation == self.generation: return
                self._eof_generation = self.generation
                if self.history_enabled and self.duration is not None and self.duration < 5 and self.current and self._history_generation != self.generation:
                    self.storage.add_history(self.current["media"])
                    self._history_generation = self.generation
                    if self.collection_changed:
                        self.collection_changed()
                if self.repeat == "one": await self._load_current(0)
                else: await self.next(False)
            elif reason == "error" and self.current_id:
                if self._retried_entry_id != self.current_id:
                    self._retried_entry_id = self.current_id
                    await self._load_current(self.position, retry=False)
                else:
                    self.state = "error"
                    self.error = {"code": "playback_error", "message": "Медиапоток оборвался; повторите или пропустите элемент"}
                    self.changed()

    async def shutdown(self) -> None:
        self.generation += 1
        tasks = [task for task in (self.resolve_task, self.history_timer, self._buffering_clear_task)
                 if task and task is not asyncio.current_task()]
        for task in tasks: task.cancel()
        if tasks: await asyncio.gather(*tasks, return_exceptions=True)
        self.persist(); await self.mpv.stop()
