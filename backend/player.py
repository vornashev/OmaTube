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
LANES = ("source", "main")


class Player:
    def __init__(
        self,
        storage: Storage,
        resolver: MediaResolver,
        mpv: MpvController,
        changed: Callable[[], None],
        collection_changed: Callable[[], None] | None = None,
        restore: bool = True,
    ) -> None:
        self.storage = storage
        self.resolver = resolver
        self.mpv = mpv
        self.changed = changed
        self.collection_changed = collection_changed
        # Two lanes: "source" is what "Play" started (a playlist, page, link); "main" is My queue,
        # the persistent list of things saved for later. One plays at a time; `queue`, `current_id`,
        # `context`, `played` and `shuffle_order` below always mean the active lane.
        self.lanes: dict[str, dict[str, Any]] = {name: self._empty_lane() for name in LANES}
        self.lane = "source"
        self.state = "idle"; self.position = 0.0; self.duration: float | None = None; self.can_seek = False
        self.volume = 100.0; self.muted = False; self.shuffle = False; self.repeat = "off"
        self.error: dict[str, str] | None = None
        self.queue_revision = 0; self.generation = 0
        # A one-shot event for the UI (finished item removed, lane switched) with what Undo needs.
        self.notice: dict[str, Any] | None = None; self._notice_serial = 0
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
        self.speed = 1.0; self.normalize = False; self.skip_silence = False
        self.sleep_mode: str | None = None; self.sleep_ends_at: float | None = None
        self.sleep_task: asyncio.Task[None] | None = None
        self.info: dict[str, Any] = {"entryId": None, "description": "", "chapters": []}
        self.sponsor_fetch: Callable[[str, list[str]], Any] | None = None
        self.sponsor_actions: dict[str, str] = {}
        self.segments: list[dict[str, Any]] = []
        self.sponsor_ignored: set[str] = set()
        self.sponsor_done: set[str] = set()
        self.sponsor_last: dict[str, Any] | None = None
        self.sponsor_pending: dict[str, Any] | None = None
        self.sponsor_saved = 0.0
        self.segments_task: asyncio.Task[None] | None = None
        self._listen_video: str | None = None; self._listen_t: float | None = None; self._listen_acc = 0.0
        if restore: self._restore()

    def _restore(self) -> None:
        try: snapshot = self.storage.load_player_state()
        except OmaTubeError as error:
            self.error = error.as_dict(); return
        if not snapshot: return
        try:
            if isinstance(snapshot.get("lanes"), dict):
                for name in LANES: self.lanes[name] = self._parse_lane(snapshot["lanes"].get(name) or {})
                self.lane = snapshot.get("lane") if snapshot.get("lane") in LANES else "source"
            else:
                # Before lanes there was one queue: a playlist's stays "Now playing", anything else was saved by hand.
                legacy = self._parse_lane(snapshot)
                self.lane = "source" if legacy["context"] else "main"
                self.lanes[self.lane] = legacy
            self.position = max(0.0, float(snapshot.get("position", 0)))
            self.volume = max(0.0, min(100.0, float(snapshot.get("volume", 100))))
            self.muted = bool(snapshot.get("muted", False)); self.shuffle = bool(snapshot.get("shuffle", False))
            self.repeat = snapshot.get("repeat") if snapshot.get("repeat") in {"off", "one", "all"} else "off"
            mode = snapshot.get("videoMode", "audio")
            self.video_mode = mode if mode in {"audio", "tile", "floating"} else "audio"
            self.state = "paused" if self.current_id else "idle"
        except (TypeError, ValueError, AttributeError):
            self.lanes = {name: self._empty_lane() for name in LANES}; self.lane = "source"; self.state = "idle"
            self.error = {"code": "storage_error", "message": "Сохранённое состояние плеера повреждено"}

    @staticmethod
    def _empty_lane() -> dict[str, Any]:
        return {"queue": [], "currentEntryId": None, "context": None, "played": [], "shuffleOrder": [], "position": 0.0, "ended": False}

    @staticmethod
    def _parse_lane(data: dict[str, Any]) -> dict[str, Any]:
        queue = data.get("queue", [])
        if not isinstance(queue, list) or any(not isinstance(row.get("entryId"), str) or not isinstance(row.get("media"), dict) for row in queue):
            raise ValueError
        ids = {row["entryId"] for row in queue}
        context = data.get("context")
        return {"queue": queue, "currentEntryId": data.get("currentEntryId") if data.get("currentEntryId") in ids else None,
                "context": context if isinstance(context, dict) and isinstance(context.get("id"), str) else None,
                "played": [item for item in data.get("played", []) if item in ids],
                "shuffleOrder": [item for item in data.get("shuffleOrder", []) if item in ids],
                "position": max(0.0, float(data.get("position", 0))),
                # Played to the end (not paused for a video), so My queue running out must not bring it back.
                "ended": data.get("ended") is True}

    @property
    def queue(self) -> list[dict[str, Any]]: return self.lanes[self.lane]["queue"]
    @queue.setter
    def queue(self, value: list[dict[str, Any]]) -> None: self.lanes[self.lane]["queue"] = value

    @property
    def current_id(self) -> str | None: return self.lanes[self.lane]["currentEntryId"]
    @current_id.setter
    def current_id(self, value: str | None) -> None: self.lanes[self.lane]["currentEntryId"] = value

    # What the lane was built from (a playlist), so lists can show "playing · 3 of 40".
    @property
    def context(self) -> dict[str, Any] | None: return self.lanes[self.lane]["context"]
    @context.setter
    def context(self, value: dict[str, Any] | None) -> None: self.lanes[self.lane]["context"] = value

    @property
    def played(self) -> list[str]: return self.lanes[self.lane]["played"]
    @played.setter
    def played(self, value: list[str]) -> None: self.lanes[self.lane]["played"] = value

    @property
    def shuffle_order(self) -> list[str]: return self.lanes[self.lane]["shuffleOrder"]
    @shuffle_order.setter
    def shuffle_order(self, value: list[str]) -> None: self.lanes[self.lane]["shuffleOrder"] = value

    @property
    def current(self) -> dict[str, Any] | None:
        return next((row for row in self.queue if row["entryId"] == self.current_id), None)

    def snapshot(self) -> dict[str, Any]:
        self.lanes[self.lane]["position"] = self.position
        return {"lane": self.lane, "lanes": self.lanes, "position": self.position,
                "volume": self.volume, "muted": self.muted, "shuffle": self.shuffle, "repeat": self.repeat,
                "videoMode": self.video_mode}

    def _track_listening(self) -> None:
        now = time.monotonic(); current = self.current
        video_id = current["media"].get("videoId") if current else None
        if video_id != self._listen_video: self._flush_listening(); self._listen_video = video_id; self._listen_t = None
        if self.state == "playing" and not self.buffering and video_id:
            if self._listen_t is not None and now - self._listen_t < 5: self._listen_acc += now - self._listen_t
            self._listen_t = now
        else:
            self._listen_t = None

    def _flush_listening(self) -> None:
        if self._listen_video and self._listen_acc >= 1:
            self.storage.add_listening(self._listen_video, self._listen_acc)
        self._listen_acc = 0.0

    def persist(self, force: bool = True) -> None:
        now = time.monotonic()
        if force or now - self._last_position_save >= 5:
            self._flush_listening()
            self.storage.save_player_state(self.snapshot()); self._last_position_save = now
            current = self.current
            if current and self.duration and self.position > 5 and current["media"].get("videoId"):
                self.storage.save_progress(current["media"]["videoId"], self.position, self.duration)
            context = self.context_status()
            if context and current and context.get("kind") == "playlist":
                self.storage.save_playlist_resume(context["id"], context["index"] - 1, current["media"].get("videoId"), self.position)

    def status(self) -> dict[str, Any]:
        return {"state": self.state, "current": self.current, "position": self.position,
                "duration": self.duration, "volume": self.volume, "muted": self.muted,
                "shuffle": self.shuffle, "repeat": self.repeat, "canSeek": self.can_seek,
                "queueRevision": self.queue_revision, "error": self.error, "videoMode": self.video_mode,
                "buffering": self.buffering, "speed": self.speed,
                "sleepTimer": {"mode": self.sleep_mode, "endsAt": self.sleep_ends_at} if self.sleep_mode else None,
                "info": self.info if self.info.get("entryId") == self.current_id else None,
                "sponsor": self.sponsor_status(), "context": self.context_status(),
                "lane": self.lane, "lanes": self.lanes_status(), "notice": self.notice}

    def context_status(self, lane: str | None = None) -> dict[str, Any] | None:
        data = self.lanes[lane or self.lane]
        if not data["context"]: return None
        index = next((i for i, row in enumerate(data["queue"]) if row["entryId"] == data["currentEntryId"]), -1)
        if index < 0: return None
        return {**data["context"], "index": int(data["context"].get("offset", 0)) + index + 1}

    def lanes_status(self) -> dict[str, Any]:
        """Both lanes in brief, so the rail can show My queue while a playlist plays and vice versa."""
        main = self.lanes["main"]["queue"]
        current = next((row for row in main if row["entryId"] == self.lanes["main"]["currentEntryId"]), main[0] if main else None)
        durations = [row["media"].get("duration") for row in main]
        return {"main": {"count": len(main),
                         "duration": sum(value for value in durations if isinstance(value, (int, float))) or None,
                         "next": current["media"].get("title") if current else None},
                "source": {"count": len(self.lanes["source"]["queue"]), "context": self.context_status("source")}}

    def _notify(self, kind: str, **fields: Any) -> None:
        self._notice_serial += 1
        self.notice = {"id": self._notice_serial, "kind": kind, **fields}

    def sponsor_upcoming(self) -> dict[str, Any] | None:
        """The next auto-skipped segment starting within 3 s, so the UI can offer to keep it once."""
        if self.state != "playing": return None
        for row in self.segments:
            if self.sponsor_actions.get(row["category"], "off") != "skip": continue
            if row["id"] in self.sponsor_ignored or row["id"] in self.sponsor_done: continue
            if 0 < row["start"] - self.position <= 3:
                return {"id": row["id"], "category": row["category"], "start": row["start"], "end": row["end"]}
        return None

    def sponsor_status(self) -> dict[str, Any] | None:
        if not self.segments and not self.sponsor_last: return None
        return {"segments": [{"start": row["start"], "end": row["end"], "category": row["category"],
                              "action": self.sponsor_actions.get(row["category"], "off")} for row in self.segments],
                "lastSkip": self.sponsor_last, "pending": self.sponsor_pending, "upcoming": self.sponsor_upcoming(),
                "saved": round(self.sponsor_saved, 1)}

    def _reset_sponsor(self) -> None:
        if self.segments_task: self.segments_task.cancel(); self.segments_task = None
        self.segments = []; self.sponsor_ignored = set(); self.sponsor_done = set()
        self.sponsor_last = None; self.sponsor_pending = None

    def _start_segments(self, entry_id: str, video_id: str, generation: int) -> None:
        fetch = self.sponsor_fetch
        categories = [name for name, action in self.sponsor_actions.items() if action != "off"]
        if not fetch or not categories: return
        async def load() -> None:
            rows = await fetch(video_id, categories)
            if generation == self.generation and self.current_id == entry_id and rows:
                self.segments = rows; self.changed()
        self.segments_task = asyncio.create_task(load())

    async def _check_segments(self, position: float) -> None:
        if not self.segments or not self.can_seek: return
        pending = None
        for row in self.segments:
            action = self.sponsor_actions.get(row["category"], "off")
            if action == "off" or row["id"] in self.sponsor_ignored: continue
            if not row["start"] <= position < row["end"] - 0.5: continue
            if action == "skip" and row["id"] not in self.sponsor_done:
                await self._skip_segment(row)
                return
            if action == "ask": pending = row
        if pending != self.sponsor_pending and (pending is None or pending["id"] not in self.sponsor_done):
            self.sponsor_pending = pending; self.changed()

    async def _skip_segment(self, row: dict[str, Any]) -> None:
        self.sponsor_done.add(row["id"]); self.sponsor_pending = None
        saved = row["end"] - row["start"]; self.sponsor_saved += saved; self.storage.add_sponsor_saving(saved)
        self.sponsor_last = {"id": row["id"], "category": row["category"], "start": row["start"], "end": row["end"], "seconds": round(saved, 1)}
        await self.mpv.seek(row["end"]); self.position = row["end"]; self.changed()

    async def sponsor_skip(self) -> None:
        if self.sponsor_pending: await self._skip_segment(self.sponsor_pending)

    async def sponsor_dismiss(self) -> None:
        if self.sponsor_pending:
            self.sponsor_ignored.add(self.sponsor_pending["id"]); self.sponsor_pending = None; self.changed()

    def sponsor_keep(self, segment_id: str) -> None:
        if any(row["id"] == segment_id for row in self.segments):
            self.sponsor_ignored.add(segment_id); self.changed()

    async def sponsor_undo(self) -> None:
        last = self.sponsor_last
        if not last: return
        self.sponsor_ignored.add(last["id"]); self.sponsor_saved = max(0.0, self.sponsor_saved - last["seconds"])
        self.sponsor_last = None
        await self.mpv.seek(last["start"]); self.position = last["start"]; self.changed()

    async def set_speed(self, value: float) -> None:
        if not 0.25 <= value <= 3.0: raise OmaTubeError("invalid_request", "Скорость должна быть от 0.25 до 3")
        self.speed = value
        if self.mpv.writer: await self.mpv.set_speed(value)
        self.changed()

    async def set_audio_options(self, normalize: bool, skip_silence: bool) -> None:
        self.normalize = normalize; self.skip_silence = skip_silence
        if self.mpv.writer: await self.mpv.set_audio_filters(normalize, skip_silence)
        self.changed()

    async def set_sleep(self, mode: Any, minutes: Any = None) -> None:
        if self.sleep_task and self.sleep_task is not asyncio.current_task(): self.sleep_task.cancel()
        self.sleep_task = None; self.sleep_mode = None; self.sleep_ends_at = None
        if mode == "timer":
            if type(minutes) is not int or not 1 <= minutes <= 720: raise OmaTubeError("invalid_request", "Таймер от 1 до 720 минут")
            self.sleep_mode = "timer"; self.sleep_ends_at = time.time() + minutes * 60
            async def fire() -> None:
                await asyncio.sleep(minutes * 60)
                self.sleep_mode = None; self.sleep_ends_at = None; self.sleep_task = None
                await self.pause()
            self.sleep_task = asyncio.create_task(fire())
        elif mode == "after_track": self.sleep_mode = "after_track"
        elif mode not in (None, "off"): raise OmaTubeError("invalid_request", "Неизвестный режим таймера")
        self.changed()


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

    async def replace_many(self, media: list[dict[str, Any]], start: float = 0.0,
                           context: dict[str, Any] | None = None) -> dict[str, Any]:
        entries = [self._entry(item) for item in media]
        if not entries:
            raise OmaTubeError("not_found", "Очередь пуста")
        # "Play" always fills Now playing; My queue keeps its items and the position of the one left.
        self._leave_lane()
        self.lane = "source"
        self.lanes["source"]["ended"] = False
        self.queue = entries
        self.context = context
        self.current_id = entries[0]["entryId"]
        self.shuffle_order = []
        self.played = []
        self.queue_revision += 1
        self.persist()
        await self._load_current(max(0.0, start))
        return entries[0]

    async def replace(self, media: dict[str, Any], start: float = 0.0) -> dict[str, Any]:
        return await self.replace_many([media], start)

    async def play_first(self, media: dict[str, Any], start: float = 0.0) -> dict[str, Any]:
        """Put the video at the head of My queue and play it; what was playing there moves to second
        and later resumes from its saved position. A copy already waiting in My queue is moved, not duplicated."""
        async with self._transition_lock:
            if self.lane == "main": self._finish_current()
            else: self._leave_lane()
            data = self.lanes["main"]; rows = data["queue"]
            existing = next((row for row in rows if row["media"].get("videoId") == media.get("videoId")), None)
            entry = existing or self._entry(media)
            if existing: rows.remove(existing)
            entry.pop("startAt", None)
            if not start and existing: start = self._resume_start(entry)
            index = next((i for i, row in enumerate(rows) if row["entryId"] == data["currentEntryId"]), 0)
            rows.insert(index, entry)
            data["currentEntryId"] = entry["entryId"]
            self.generation += 1; self._loaded_generation = -1
            if self.resolve_task: self.resolve_task.cancel()
            self.lane = "main"
            self.queue_revision += 1; self.persist()
            await self._load_current(max(0.0, start))
        return {**entry, "position": 0, "lane": "main"}

    def enqueue(self, media: dict[str, Any], placement: str, start: float | None = None, lane: str | None = None) -> dict[str, Any]:
        """"next" goes right after the current item of the active lane; "end" saves to My queue
        unless `lane` names another one."""
        entry = self._entry(media)
        if start and start > 0: entry["startAt"] = float(start)
        if placement not in {"next", "end"}: raise OmaTubeError("invalid_request", "Неизвестное место в очереди")
        name = self._lane_name(lane) if lane else (self.lane if placement == "next" else "main")
        data = self.lanes[name]; rows = data["queue"]; current_id = data["currentEntryId"]
        if placement == "next" and current_id:
            index = next(index for index, row in enumerate(rows) if row["entryId"] == current_id)
            rows.insert(index + 1, entry)
        elif placement == "next": rows.insert(0, entry)
        else: rows.append(entry)
        if self.shuffle and name == "source":
            order = data["shuffleOrder"]
            if placement == "next" and current_id in order: order.insert(order.index(current_id) + 1, entry["entryId"])
            else: order.append(entry["entryId"])
        self.queue_revision += 1; self.persist(); self.changed()
        current = next((i for i, row in enumerate(rows) if row["entryId"] == current_id), -1)
        index = next(i for i, row in enumerate(rows) if row["entryId"] == entry["entryId"])
        return {**entry, "position": index - current, "lane": name}

    @staticmethod
    def _lane_name(value: Any) -> str:
        if value not in LANES: raise OmaTubeError("invalid_request", "Неизвестная очередь")
        return value

    def _is_complete(self) -> bool:
        """Close enough to the end to count as watched: the last 30 s, or the last 3 % of a long video."""
        if not self.duration or self.duration <= 0: return False
        return self.position >= self.duration - max(30.0, self.duration * 0.03)

    def _finish_current(self, force: bool = False) -> int | None:
        """Drop a watched item from My queue (the active lane must be "main"); returns where it stood."""
        if self.lane != "main" or not self.current or not (force or self._is_complete()): return None
        index = next(i for i, row in enumerate(self.queue) if row["entryId"] == self.current_id)
        entry = self.queue.pop(index)
        self.played = [item for item in self.played if item != entry["entryId"]]
        self.current_id = None; self.lanes["main"]["position"] = 0.0
        self.queue_revision += 1
        before = self.queue[index]["entryId"] if index < len(self.queue) else None
        self._notify("finished", lane="main", title=entry["media"].get("title"),
                     entries=[{"entry": entry, "beforeEntryId": before}])
        return index

    def _leave_lane(self) -> None:
        """Remember where the active lane stopped before another one takes over."""
        if self.lane == "main" and self._finish_current() is not None: return
        self.persist()

    async def switch_lane(self, lane: Any, play: bool = True) -> None:
        name = self._lane_name(lane)
        if name == self.lane:
            if play and self.state != "playing" and self.current_id: await self.play()
            return
        async with self._transition_lock:
            if name == "source": self.lanes["source"]["ended"] = False
            self._leave_lane(); await self._enter_lane(name, play)

    async def _enter_lane(self, name: str, play: bool) -> None:
        self.generation += 1; self._loaded_generation = -1
        if self.resolve_task: self.resolve_task.cancel()
        self.lane = name
        if not self.current and self.queue: self.current_id = self.queue[0]["entryId"]
        current = self.current
        start = self._resume_start(current) if name == "main" else self.lanes[name]["position"]
        self.queue_revision += 1
        if current and play:
            self.persist(); await self._load_current(start); return
        if self.mpv.writer: await self.mpv.stop_playback()
        self._desired_paused = True
        self.state = "paused" if current else "idle"
        self.position = start if current else 0.0; self.duration = None; self.can_seek = False
        self.persist(); self.changed()

    def _resume_start(self, entry: dict[str, Any] | None) -> float:
        """Where a My queue item continues from: its saved position unless it was (nearly) finished."""
        video_id = entry["media"].get("videoId") if entry else None
        saved = self.storage.progress_for([video_id]).get(video_id) if video_id else None
        if not saved: return 0.0
        position, duration = float(saved["position"]), float(saved["duration"])
        return position if 5 < position < duration - max(30.0, duration * 0.03) else 0.0

    async def hydrate_entry(self, entry_id: str) -> None:
        """Fill title/author/thumbnail of a queued entry that was added by bare URL."""
        find = lambda: next((row for name in LANES for row in self.lanes[name]["queue"] if row["entryId"] == entry_id), None)
        entry = find()
        if not entry: return
        try: audio = await self.resolver.resolve(entry["media"]["videoId"])
        except Exception: return
        entry = find()
        if not entry: return
        media = entry["media"]; changed = False
        for key, value in {"title": audio.title, "author": audio.author, "thumbnailUrl": audio.thumbnail_url,
                           "authorId": audio.author_id, "canonicalUrl": audio.canonical_url}.items():
            if value and media.get(key) != value and (key != "duration"):
                media[key] = value; changed = True
        if audio.duration and not media.get("duration"): media["duration"] = audio.duration; changed = True
        if changed: self.queue_revision += 1; self.persist(); self.changed()

    async def cancel_load(self) -> None:
        """Abort a stream that is still resolving; the entry stays current and play() retries it."""
        if self.state != "loading" or (self.resolve_task and self.resolve_task.done()): return
        self.generation += 1
        if self.resolve_task: self.resolve_task.cancel()
        self._desired_paused = True
        self.state = "paused"; self.changed()

    async def _load_current(self, start: float = 0.0, retry: bool = True) -> None:
        current = self.current
        if retry: self._retried_entry_id = None
        if not current: self.state = "idle"; self.changed(); return
        # A start position queued from the browser applies once, on the entry's first load.
        start_at = current.pop("startAt", None)
        if not start and isinstance(start_at, (int, float)) and start_at > 0: start = float(start_at)
        self.generation += 1; generation = self.generation; self._eof_generation = -1
        self._reset_sponsor()
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
            started = time.monotonic(); resolved_at = started
            try:
                if self.mpv.writer:
                    await self.mpv.stop_playback(preserve_window=self.video_mode != "audio")
                    if self.video_mode != "audio":
                        await self.mpv.set_video_loading(True, loader_token)
                        loader_visible = True
                if generation != self.generation: return
                audio = await self.resolver.resolve(current["media"]["videoId"])
                resolved_at = time.monotonic()
                if generation != self.generation or self.current_id != current["entryId"]: return
                media = current["media"]
                resolved_metadata = {
                    "title": audio.title, "author": audio.author,
                    "thumbnailUrl": audio.thumbnail_url, "canonicalUrl": audio.canonical_url,
                    "viewCount": audio.view_count, "likeCount": audio.like_count,
                    "authorId": audio.author_id,
                }
                changed_metadata = False
                for key, value in resolved_metadata.items():
                    if value is not None and value != "" and media.get(key) != value:
                        media[key] = value; changed_metadata = True
                if changed_metadata:
                    self.queue_revision += 1; self.persist()
                self.info = {"entryId": current["entryId"], "description": audio.description or "",
                             "chapters": list(audio.chapters), "storyboard": audio.storyboard}
                self.duration = audio.duration; self.can_seek = audio.seekable
                self._start_segments(current["entryId"], current["media"]["videoId"], generation)
                await self.mpv.load(audio, start if audio.seekable else 0, paused=self._desired_paused)
                loaded_at = time.monotonic()
                if loaded_at - started > 6:
                    LOGGER.warning("Slow start of %s: resolve %.1fs, mpv open %.1fs", current["media"]["videoId"],
                                   resolved_at - started, loaded_at - resolved_at)
                if generation != self.generation: return
                self._loaded_generation = generation
                await self.mpv.set_volume(self.volume); await self.mpv.set_mute(self.muted)
                if self.speed != 1.0: await self.mpv.set_speed(self.speed)
                if self.normalize or self.skip_silence: await self.mpv.set_audio_filters(self.normalize, self.skip_silence)
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
                self._prefetch_next()
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
        # My queue is a to-do list: always in order, whatever shuffle says.
        if not self.shuffle or self.lane == "main": return [row["entryId"] for row in self.queue]
        ids = [row["entryId"] for row in self.queue]
        retained = [item for item in self.shuffle_order if item in ids]
        missing = [item for item in ids if item not in retained]
        random.shuffle(missing)
        self.shuffle_order = retained + missing
        return self.shuffle_order

    def _prefetch_next(self) -> None:
        prefetch = getattr(self.resolver, "prefetch", None)
        if prefetch is None: return
        target = self._next_id(False)
        entry = next((row for row in self.queue if row["entryId"] == target), None) if target else None
        video_id = entry["media"].get("videoId") if entry else None
        if video_id and target != self.current_id:
            prefetch(video_id)

    def _next_id(self, manual: bool = False) -> str | None:
        order = self._ordered_ids()
        if self.current_id not in order: return order[0] if order else None
        index = order.index(self.current_id)
        if index + 1 < len(order): return order[index + 1]
        if self.repeat == "all" and self.lane == "source": return order[0] if order else None
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

    async def next(self, manual: bool = True, finished: bool = False) -> None:
        async with self._transition_lock:
            index = self._finish_current(force=finished)
            if index is not None:
                # The watched item left My queue; whatever moved into its place plays next, from where it stopped.
                if index < len(self.queue):
                    self.current_id = self.queue[index]["entryId"]
                    self.persist(); await self._load_current(self._resume_start(self.current)); return
                target = None
            else:
                target = self._next_id(manual)
            if not target and self.lane == "source" and self.lanes["main"]["queue"]:
                # Now playing ran out: carry on with My queue, the toast offers to go back.
                self._notify("laneSwitched", reason="sourceEnded", lane="main",
                             name=(self.context or {}).get("name"))
                self.lanes["source"]["position"] = 0.0; self.lanes["source"]["ended"] = True
                await self._enter_lane("main", True); return
            source = self.lanes["source"]
            if not target and self.lane == "main" and source["currentEntryId"] and not source["ended"]:
                # My queue ran out while a playlist waited, paused for a video: pick it up where it stopped.
                # This notice replaces the "finished" one, so it carries that entry for the toast's restore.
                finished = self.notice.get("entries") if index is not None and self.notice and self.notice.get("kind") == "finished" else []
                self._notify("laneSwitched", reason="queueEnded", lane="source",
                             name=(source["context"] or {}).get("name"), entries=finished or [])
                await self._enter_lane("source", True); return
            if not target:
                self.generation += 1
                self._loaded_generation = -1
                if self.resolve_task: self.resolve_task.cancel()
                self.state = "idle"; self.current_id = None; self.position = 0; self.duration = None; self.can_seek = False
                await self.mpv.stop_playback(); self.persist(); self.changed(); return
            if self.current_id: self.played.append(self.current_id)
            self.current_id = target; self.persist()
            await self._load_current(self._resume_start(self.current) if self.lane == "main" else 0)

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
        self.current_id = entry_id; self.persist()
        await self._load_current(self._resume_start(self.current) if self.lane == "main" else 0)

    def _lane_of(self, entry_id: str) -> str:
        """Entry ids are unique across lanes, so callers that only know the id needn't know the lane."""
        return next((name for name in LANES if any(row["entryId"] == entry_id for row in self.lanes[name]["queue"])), self.lane)

    async def remove(self, entry_id: str, lane: str | None = None) -> None:
        name = self._lane_name(lane) if lane else self._lane_of(entry_id)
        data = self.lanes[name]
        index = next((i for i, row in enumerate(data["queue"]) if row["entryId"] == entry_id), -1)
        if index < 0: raise OmaTubeError("not_found", "Элемент очереди не найден")
        data["queue"].pop(index)
        data["shuffleOrder"] = [item for item in data["shuffleOrder"] if item != entry_id]
        data["played"] = [item for item in data["played"] if item != entry_id]
        self.queue_revision += 1
        if entry_id == data["currentEntryId"] and name != self.lane:
            data["currentEntryId"] = None; data["position"] = 0.0
        elif entry_id == self.current_id:
            self.current_id = self.queue[min(index, len(self.queue)-1)]["entryId"] if self.queue else None
            if self.current_id: await self._load_current(self._resume_start(self.current) if name == "main" else 0)
            else: await self.clear()
        self.persist(); self.changed()

    def restore(self, rows: Any, lane: str | None = None) -> None:
        """Put removed entries back (undo); each row is {"entry", "beforeEntryId"}, applied in order."""
        if not isinstance(rows, list) or not rows: raise OmaTubeError("invalid_request", "Нечего возвращать")
        data = self.lanes[self._lane_name(lane) if lane else self.lane]
        for row in rows:
            entry = row.get("entry") if isinstance(row, dict) else None
            if not isinstance(entry, dict) or not isinstance(entry.get("entryId"), str):
                raise OmaTubeError("invalid_request", "Некорректный элемент очереди")
            self._entry(entry.get("media"))
        for row in rows:
            entry = {key: value for key, value in row["entry"].items() if key in {"entryId", "media", "startAt"}}
            ids = [item["entryId"] for item in data["queue"]]
            if entry["entryId"] in ids: continue
            before = row.get("beforeEntryId")
            data["queue"].insert(ids.index(before) if before in ids else len(data["queue"]), entry)
            if self.shuffle and data is self.lanes["source"]: data["shuffleOrder"].append(entry["entryId"])
        self.queue_revision += 1; self.persist(); self.changed()

    def move(self, entry_id: str, before_entry_id: str | None, lane: str | None = None) -> None:
        rows = self.lanes[self._lane_name(lane) if lane else self._lane_of(entry_id)]["queue"]
        ids = [row["entryId"] for row in rows]
        if entry_id not in ids or (before_entry_id is not None and before_entry_id not in ids): raise OmaTubeError("not_found", "Элемент очереди не найден")
        row = rows.pop(ids.index(entry_id)); ids.remove(entry_id)
        rows.insert(ids.index(before_entry_id) if before_entry_id else len(rows), row)
        self.queue_revision += 1; self.persist(); self.changed()

    async def clear(self, lane: str | None = None) -> None:
        name = self._lane_name(lane) if lane else self.lane
        if name != self.lane:
            self.lanes[name] = self._empty_lane(); self.queue_revision += 1
            self.persist(); self.changed(); return
        self.generation += 1
        self._loaded_generation = -1
        if self.resolve_task: self.resolve_task.cancel()
        self.lanes[name] = self._empty_lane(); self.state = "idle"; self.position = 0; self.duration = None; self.can_seek = False
        self.queue_revision += 1
        if self.mpv.writer: await self.mpv.stop_playback()
        self.persist(); self.changed()

    def set_shuffle(self, value: bool) -> None:
        # Shuffle belongs to Now playing; My queue always plays in order.
        source = self.lanes["source"]
        self.shuffle = value; source["shuffleOrder"] = []
        if value:
            source["shuffleOrder"] = [row["entryId"] for row in source["queue"]]; random.shuffle(source["shuffleOrder"])
        self.persist(); self.changed()

    def set_repeat(self, value: str) -> None:
        if value not in {"off", "one", "all"}: raise OmaTubeError("invalid_request", "Некорректный режим повтора")
        self.repeat = value; self.persist(); self.changed()

    async def reload_current(self) -> None:
        if not self.current:
            return
        self._desired_paused = self.state == "paused" or self._desired_paused
        await self._load_current(self.position, retry=False)

    def prefer_video_mode(self, value: str) -> None:
        """Choose the mode for the next load without touching the current mpv surface."""
        if value not in {"audio", "tile", "floating"}:
            raise OmaTubeError("invalid_request", "Некорректный режим видео")
        self.video_mode = value

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
                    if error.code == "playback_error" and "отклонил" in error.message and self.current and value != "audio":
                        # The video stream URL most likely went stale: resolve fresh links once.
                        self.video_mode = value; self.error = None
                        self.persist(); self.changed()
                        await self.reload_current()
                        return
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
            if name == "time-pos" and isinstance(value, (int, float)):
                self.position = float(value); self._track_listening(); self.persist(False)
                await self._check_segments(self.position)
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
                if self.sleep_mode == "after_track":
                    self.sleep_mode = None
                    await self.next(False, finished=True); await self.pause()
                elif self.repeat == "one" and self.lane == "source": await self._load_current(0)
                else: await self.next(False, finished=True)
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
        tasks = [task for task in (self.resolve_task, self.history_timer, self._buffering_clear_task, self.sleep_task, self.segments_task)
                 if task and task is not asyncio.current_task()]
        for task in tasks: task.cancel()
        if tasks: await asyncio.gather(*tasks, return_exceptions=True)
        self.persist(); await self.mpv.stop()
