from __future__ import annotations

import argparse
import asyncio
import json
import traceback
import os
from pathlib import Path
import signal
import time
from typing import Any, Awaitable, Callable
from uuid import uuid4

from .auth import YouTubeAuth
from .subscription_import import fetch_channels
from .net import HttpClient, ImageCache, ImageServer
from . import feed as feed_module, sponsorblock as sponsorblock_module, lyrics as lyrics_module
from .catalog import CatalogBridge
from .errors import OmaTubeError
from .mpris import MprisBridge
from .mpv import MpvController
from .player import Player
from .resolver import MediaResolver, VIDEO_QUALITIES
from .storage import Storage
from .downloads import DownloadManager
from .feed import FeedService
from .lyrics import LyricsService
from .sponsorblock import ACTIONS as SPONSOR_ACTIONS, CATEGORIES as SPONSOR_CATEGORIES, DEFAULT_ACTIONS as SPONSOR_DEFAULTS, SponsorBlock
from .urls import normalize_youtube_url

MAX_REQUEST = 64 * 1024
MAX_RESPONSE = 8 * 1024 * 1024
DEFAULT_PREFERENCES = {
    "showCover": True, "showAuthor": True, "showTitle": True, "showControls": True,
    "showProgress": True, "textWidth": 220, "marquee": False, "historyEnabled": True,
    "videoQuality": 1080, "panelFormat": "wide", "searchView": "grid", "onboarded": False,
    "normalize": False, "skipSilence": False,
    "barLayout": "full", "hideWhenIdle": False, "wheelVolume": False, "hoverPrefetch": True, "restoreQueue": True,
    "sponsorActions": dict(SPONSOR_DEFAULTS),
    "downloadKind": "audio",
    "browserAccept": True, "browserNotify": True, "browserVideoMode": "keep",
    "playerDock": "thin", "language": "auto", "recentSearches": [],
}
CHOICE_PREFERENCES = {
    "panelFormat": {"wide", "compact", "shelf"},
    "barLayout": {"full", "title", "icon"},
    "downloadKind": {"audio", "video"},
    "searchView": {"grid", "list"},
    "playerDock": {"thin", "bar"},
    "language": {"auto", "en", "ru"},
    "browserVideoMode": {"keep", "audio", "tile", "floating"},
}
RECENT_SEARCHES = 8
MAX_START = 24 * 3600
MEDIA_HINT_LIMITS = {"title": 300, "author": 200, "authorId": 64}
VIEW_OPERATION_KINDS = {
    "entity_section",
    "search",
    "open_entity",
    "play_url",
    "enqueue_url",
    "search_more",
    "entity_more",
}


class Backend:
    def __init__(self, app_root: Path) -> None:
        runtime_env = os.environ.get("XDG_RUNTIME_DIR")
        if not runtime_env: raise OmaTubeError("dependency_missing", "XDG_RUNTIME_DIR не задан")
        data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "omatube"
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "omatube"
        self.runtime = Path(runtime_env) / "omatube"; self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.runtime.chmod(0o700); data_home.mkdir(parents=True, exist_ok=True, mode=0o700); config_home.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.socket_path = self.runtime / "backend.sock"
        self.preferences_path = config_home / "preferences.json"
        self.preferences = self._load_preferences()
        if type(self.preferences["videoQuality"]) is not int or self.preferences["videoQuality"] not in VIDEO_QUALITIES:
            self.preferences["videoQuality"] = 1080
        self.storage = Storage(data_home / "library.sqlite3")
        proxy = os.environ.get("OMATUBE_PROXY") or os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
        self.catalog = CatalogBridge(app_root / "catalog/worker.mjs", proxy=proxy)
        python = app_root / ".venv/bin/python"
        if not python.exists(): python = Path(os.environ.get("OMATUBE_PYTHON", os.sys.executable))
        self.python = python; self.proxy = proxy
        self.youtube_auth = YouTubeAuth(python, config_home)
        self.resolver = MediaResolver(
            python,
            proxy=proxy,
            cookies_path=self.youtube_auth.path,
            max_video_height=self.preferences["videoQuality"],
        )
        self.mpv: MpvController
        self.player: Player
        self.mpris: MprisBridge | None = None
        self.backend_session_id = str(uuid4())
        self.catalog_revision = 0
        self.collection_revision = 0
        self.views: dict[str, dict[str, Any]] = {}
        self.operations: dict[str, dict[str, Any]] = {}
        self.retained_operation_ids: tuple[str, ...] = ()
        self.maintenance_tasks: set[asyncio.Task[None]] = set()
        self.catalog_warm_task: asyncio.Task[Any] | None = None
        self.mpv = MpvController(self.runtime / "mpv.sock", self._mpv_event, proxy=proxy)
        self.player = Player(
            self.storage,
            self.resolver,
            self.mpv,
            self._changed,
            self._collection_changed,
            restore=self.preferences.get("restoreQueue", True) is not False,
        )
        self.player.history_enabled = bool(self.preferences["historyEnabled"])
        if not isinstance(self.preferences.get("sponsorActions"), dict):
            self.preferences["sponsorActions"] = dict(SPONSOR_DEFAULTS)
        self.preferences["sponsorActions"] = {**SPONSOR_DEFAULTS, **{k: v for k, v in self.preferences["sponsorActions"].items() if k in SPONSOR_CATEGORIES and v in SPONSOR_ACTIONS}}
        self.http = HttpClient(proxy)
        self.net_stats = (self.catalog.stats, self.resolver.stats)
        self.image_cache = ImageCache(data_home / "cache" / "images", self.http)
        self.image_server = ImageServer(self.image_cache, int(os.environ.get("OMATUBE_IMAGE_PORT") or 47865))
        self.lyrics_service = LyricsService(fetcher=lyrics_module.client_fetcher(self.http))
        self.feed_service = FeedService(fetcher=feed_module.client_fetcher(self.http)); self.feed_task: asyncio.Task[None] | None = None
        download_dir = Path(os.environ.get("OMATUBE_DOWNLOAD_DIR") or Path.home() / "Videos" / "OmaTube")
        self.downloads = DownloadManager(self.storage, download_dir, python, self.youtube_auth.path, proxy, self._changed,
                                         quality=lambda: self.preferences["videoQuality"])
        self.sponsorblock = SponsorBlock(fetcher=sponsorblock_module.client_fetcher(self.http))
        self.player.sponsor_fetch = self.sponsorblock.segments
        self.player.sponsor_actions = self.preferences["sponsorActions"]
        self.player.normalize = bool(self.preferences["normalize"]); self.player.skip_silence = bool(self.preferences["skipSilence"])
        self.server: asyncio.AbstractServer | None = None

    def _load_preferences(self) -> dict[str, Any]:
        result = DEFAULT_PREFERENCES.copy()
        try:
            value = json.loads(self.preferences_path.read_text(encoding="utf-8"))
            if isinstance(value, dict): result.update({key: value[key] for key in result.keys() & value.keys()})
        except (FileNotFoundError, json.JSONDecodeError, OSError): pass
        return result

    def _save_preferences(self) -> None:
        temporary = self.preferences_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.preferences, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.chmod(0o600); temporary.replace(self.preferences_path)

    async def _mpv_event(self, event: dict[str, Any]) -> None: await self.player.handle_mpv_event(event)

    def _changed(self) -> None:
        if self.mpris:
            try: self.mpris.notify()
            except Exception: pass

    def _collection_changed(self) -> None:
        self.collection_revision += 1
        self._changed()

    def status(self) -> dict[str, Any]:
        return {
            **self.player.status(),
            "backendSessionId": self.backend_session_id,
            "catalogRevision": self.catalog_revision,
            "collectionRevision": self.collection_revision,
            "newCount": self.storage.new_count(),
            **self._downloads_brief(),
            "netSlow": any(stats.slow for stats in self.net_stats),
            "imagePort": self.image_server.port,
            "preferences": self.preferences,
            "youtubeAuth": self.youtube_auth.status(),
        }

    def _downloads_brief(self) -> dict[str, Any]:
        brief = self.downloads.brief()
        return {"downloadsActive": brief["active"], "downloadsFailed": brief["failed"], "downloadsProgress": brief["progress"]}

    @staticmethod
    def _view_cursors(view: dict[str, Any]) -> set[str]:
        cursors: set[str] = set()
        cursor = view.get("nextCursor")
        if isinstance(cursor, str) and cursor:
            cursors.add(cursor)
        sections = view.get("sections")
        if isinstance(sections, dict):
            for section in sections.values():
                if not isinstance(section, dict):
                    continue
                cursor = section.get("nextCursor")
                if isinstance(cursor, str) and cursor:
                    cursors.add(cursor)
        return cursors

    def _release_cursors(self, cursors: set[str]) -> None:
        if not cursors:
            return

        async def release() -> None:
            for cursor in cursors:
                try:
                    await self.catalog.request("release", {"cursor": cursor})
                except OmaTubeError:
                    pass

        task = asyncio.create_task(release())
        self.maintenance_tasks.add(task)
        task.add_done_callback(self.maintenance_tasks.discard)

    def _prune_operations(self) -> None:
        retained = {
            operation_id
            for operation_id in self.retained_operation_ids
            if operation_id in self.operations
        }
        running = {
            operation_id
            for operation_id, record in self.operations.items()
            if record.get("state") == "running"
        }
        other_terminal = [
            operation_id
            for operation_id, record in self.operations.items()
            if record.get("state") != "running" and operation_id not in retained
        ]
        keep = retained | running | set(other_terminal[-32:])
        removed_operations = [
            operation_id
            for operation_id in self.operations
            if operation_id not in keep
        ]
        for operation_id in removed_operations:
            self.operations.pop(operation_id, None)

        reachable_views: set[str] = set()
        for record in self.operations.values():
            result = record.get("result")
            if isinstance(result, dict) and isinstance(result.get("viewId"), str):
                reachable_views.add(result["viewId"])
            if record.get("state") == "running":
                request = record.get("request")
                if isinstance(request, dict) and isinstance(request.get("viewId"), str):
                    reachable_views.add(request["viewId"])

        removed_views = [
            view_id for view_id in self.views if view_id not in reachable_views
        ]
        if removed_views:
            retained_cursors = set().union(*(
                self._view_cursors(view)
                for view_id, view in self.views.items()
                if view_id in reachable_views
            ))
            removed_cursors = set().union(*(
                self._view_cursors(self.views[view_id])
                for view_id in removed_views
            ))
            self._release_cursors(removed_cursors - retained_cursors)
            for view_id in removed_views:
                self.views.pop(view_id, None)

        if removed_operations or removed_views:
            self.catalog_revision += 1

    def details(self, request: dict[str, Any] | None = None) -> dict[str, Any]:
        if request is not None and not isinstance(request, dict):
            raise OmaTubeError("invalid_request", "Некорректный запрос details")
        request = request or {}
        known = request.get("knownRevisions")
        if known is not None:
            if not isinstance(known, dict):
                raise OmaTubeError("invalid_request", "Некорректные ревизии details")
            expected_types = {
                "backendSessionId": str,
                "queueRevision": int,
                "catalogRevision": int,
                "collectionRevision": int,
            }
            for key, expected_type in expected_types.items():
                if key in known and (
                    not isinstance(known[key], expected_type)
                    or (expected_type is int and isinstance(known[key], bool))
                ):
                    raise OmaTubeError("invalid_request", "Некорректные ревизии details")

        retained_changed = False
        if "retainedOperationIds" in request:
            retained_value = request["retainedOperationIds"]
            if (
                not isinstance(retained_value, list)
                or any(not isinstance(value, str) for value in retained_value)
            ):
                raise OmaTubeError("invalid_request", "Некорректные operationId")
            normalized: list[str] = []
            for operation_id in retained_value:
                if operation_id in self.operations and operation_id not in normalized:
                    normalized.append(operation_id)
                if len(normalized) == 8:
                    break
            next_retained = tuple(normalized)
            retained_changed = next_retained != self.retained_operation_ids
            self.retained_operation_ids = next_retained

        self._prune_operations()
        result = self.status()
        full = (
            known is None
            or known.get("backendSessionId") != self.backend_session_id
        )
        if full or known.get("queueRevision") != self.player.queue_revision:
            result["queue"] = self.player.queue
            result["mainQueue"] = self.player.lanes["main"]["queue"]
        if full or known.get("collectionRevision") != self.collection_revision:
            result["savedIds"] = self.storage.saved_media_ids()
        if (
            full
            or known.get("catalogRevision") != self.catalog_revision
            or retained_changed
        ):
            result["views"] = self.views
            result["operations"] = [
                {
                    key: value
                    for key, value in record.items()
                    if key != "task"
                }
                for record in self.operations.values()
            ]
        return result

    def _operation(self, kind: str, request: dict[str, Any],
                   runner: Callable[[], Awaitable[Any]]) -> dict[str, Any]:
        operation_id = str(uuid4())
        operation_request = {key: value for key, value in request.items() if key != "command"}
        record = {
            "operationId": operation_id,
            "kind": kind,
            "request": operation_request,
            "state": "running",
            "startedAt": time.time(),
            "finishedAt": None,
            "processed": 0,
            "result": None,
            "error": None,
        }
        self.operations[operation_id] = record; self.catalog_revision += 1
        async def execute() -> None:
            try:
                result = await runner()
                if (
                    kind in VIEW_OPERATION_KINDS
                    and isinstance(result, dict)
                    and isinstance(result.get("viewId"), str)
                ):
                    result = {"viewId": result["viewId"]}
                record["result"] = result
                record["state"] = "done"
            except asyncio.CancelledError:
                record["state"] = "cancelled"
            except OmaTubeError as error:
                record["state"] = "failed"
                record["error"] = error.as_dict()
            except Exception:
                record["state"] = "failed"
                record["error"] = {
                    "code": "provider_error",
                    "message": "Операция OmaTube завершилась ошибкой",
                }
            finally:
                record["finishedAt"] = time.time()
                record.pop("task", None)
                self.catalog_revision += 1
                self._prune_operations()
                self._changed()
        record["task"] = asyncio.create_task(execute())
        return {"accepted": True, "operationId": operation_id}

    @staticmethod
    def _media(value: Any) -> dict[str, Any]:
        if not isinstance(value, dict) or not isinstance(value.get("videoId"), str):
            raise OmaTubeError("invalid_request", "Некорректное медиа")
        return value

    async def command(self, request: dict[str, Any]) -> Any:
        command = request.get("command")
        if command == "status": return self.status()
        if command == "details": return self.details(request)
        if command in {"play_url", "enqueue_url"}:
            from_browser = request.get("origin") == "browser"
            if from_browser and not self.preferences["browserAccept"]:
                raise OmaTubeError("disabled", "Приём видео из браузера выключен в настройках OmaTube")
            normalized = normalize_youtube_url(request.get("url", ""))
            start = self._start(request.get("start"), normalized.get("start"))
            if normalized["kind"] == "playlist":
                entity = {"source": "youtube", "kind": "playlist", "id": normalized["id"], "title": "Плейлист YouTube", "author": "", "thumbnailUrl": None, "canonicalUrl": normalized["canonicalUrl"]}
                return self._operation(command, request, lambda: self._open_entity(entity))
            media = {"videoId": normalized["videoId"], "source": "youtube", "title": normalized["videoId"],
                     "author": "Автор неизвестен", "authorId": None, "duration": None, "thumbnailUrl": None,
                     "canonicalUrl": normalized["canonicalUrl"], **self._media_hints(request.get("media"))}
            if from_browser and command == "play_url" and self.preferences["browserVideoMode"] not in {"keep", self.player.video_mode}:
                self.player.prefer_video_mode(self.preferences["browserVideoMode"])
            if command == "play_url":
                # From the browser "now" means the head of My queue, not a new Now playing list.
                if request.get("placement") == "first": return await self.player.play_first(media, start)
                return await self.player.replace(media, start)
            queued = self.player.enqueue(media, request.get("placement", "end"), start)
            if media["title"] == media["videoId"] or media["author"] == "Автор неизвестен":
                self._background(self.player.hydrate_entry(queued["entryId"]))
            return queued
        if command in {"play", "pause", "toggle_pause", "next", "previous", "queue_clear"}:
            if command == "play": await self.player.play()
            elif command == "pause": await self.player.pause()
            elif command == "toggle_pause": await (self.player.pause() if self.player.state == "playing" else self.player.play())
            elif command == "next": await self.player.next(True)
            elif command == "previous": await self.player.previous()
            else: await self.player.clear(request.get("lane"))
            return self.player.status()
        if command == "seek": await self.player.seek(float(request.get("seconds", 0))); return self.player.status()
        if command == "youtube_auth_import":
            browser = request.get("browser", "chromium")
            if not isinstance(browser, str):
                raise OmaTubeError("invalid_request", "Некорректный браузер")
            return self._operation(
                command, request,
                lambda: self.youtube_auth.import_from_browser(browser),
            )
        if command == "youtube_auth_clear":
            return await self.youtube_auth.clear()
        if command == "video_mode":
            value = request.get("value")
            if not isinstance(value, str) or value not in {"audio", "tile", "floating"}:
                raise OmaTubeError("invalid_request", "Некорректный режим видео")
            return self._operation(command, request, lambda: self.player.set_video_mode(value))
        if command == "video_quality":
            value = request.get("value")
            if type(value) is not int or value not in VIDEO_QUALITIES:
                raise OmaTubeError("invalid_request", "Некорректное качество видео")
            return self._operation(command, request, lambda: self._set_video_quality(value))
        if command == "sponsor_keep": self.player.sponsor_keep(str(request.get("id", ""))); return self.player.status()
        if command == "cancel_load": await self.player.cancel_load(); return self.player.status()
        if command in {"sponsor_undo", "sponsor_skip", "sponsor_dismiss"}:
            await getattr(self.player, command)(); return self.player.status()
        if command == "speed":
            value = request.get("value")
            if isinstance(value, bool) or not isinstance(value, (int, float)): raise OmaTubeError("invalid_request", "Некорректная скорость")
            await self.player.set_speed(float(value)); return self.player.status()
        if command == "sleep_timer":
            await self.player.set_sleep(request.get("mode"), request.get("minutes")); return self.player.status()
        if command == "volume":
            value = float(request.get("value", -1))
            if not 0 <= value <= 100: raise OmaTubeError("invalid_request", "Громкость должна быть от 0 до 100")
            self.player.volume = value; await self.mpv.set_volume(value); self.player.persist(); self._changed(); return self.player.status()
        if command == "mute":
            value = request.get("value")
            if not isinstance(value, bool): raise OmaTubeError("invalid_request", "Некорректное значение mute")
            self.player.muted = value; await self.mpv.set_mute(value); self.player.persist(); self._changed(); return self.player.status()
        if command == "queue_play": await self.player.play_entry(str(request.get("entryId", ""))); return self.player.status()
        if command == "queue_remove": await self.player.remove(str(request.get("entryId", "")), request.get("lane")); return self.player.status()
        if command == "queue_restore": self.player.restore(request.get("entries"), request.get("lane")); return self.player.status()
        if command == "queue_move": self.player.move(str(request.get("entryId", "")), request.get("beforeEntryId"), request.get("lane")); return self.player.status()
        if command == "lane_switch": await self.player.switch_lane(request.get("lane"), request.get("play") is not False); return self.player.status()
        if command == "shuffle": self.player.set_shuffle(bool(request.get("value"))); return self.player.status()
        if command == "repeat": self.player.set_repeat(str(request.get("value"))); return self.player.status()
        if command == "suggestions":
            source = str(request.get("source")); query = str(request.get("query", "")).strip()
            return self._operation(command, request, lambda: self.catalog.request("suggestions", {"source": source, "query": query}))
        if command == "search":
            return self._operation(command, request, lambda: self._search(request))
        if command in {"search_more", "entity_more"}:
            view_id = str(request.get("viewId", ""))
            existing = next((
                record
                for record in self.operations.values()
                if record.get("state") == "running"
                and record.get("kind") in {"search_more", "entity_more"}
                and str(record.get("request", {}).get("viewId", "")) == view_id
            ), None)
            if existing:
                return {
                    "accepted": True,
                    "operationId": existing["operationId"],
                }
            return self._operation(
                command,
                request,
                lambda: self._more(view_id),
            )
        if command == "entity_section":
            view_id = str(request.get("viewId", "")); tab = str(request.get("tab", "")); sort = request.get("sort")
            return self._operation(command, request, lambda: self._entity_section(view_id, tab, str(sort) if sort else None))
        if command == "open_entity":
            return self._operation(
                command,
                request,
                lambda: self._open_entity(request.get("entity")),
            )
        if command == "play_view": return await self._play_view(str(request.get("viewId", "")), request.get("entryId"))
        if command == "save_media":
            saved = bool(request.get("saved"))
            self.storage.save_media(self._media(request.get("media")), saved)
            self._collection_changed()
            return {"saved": saved}
        if command == "collection":
            return self.storage.collection(
                str(request.get("section")),
                int(request.get("offset", 0)),
            )
        if command == "history_remove":
            self.storage.remove_history_entry(str(request.get("playId", ""))); self._collection_changed()
            return {"removed": True}
        if command == "stats":
            result = self.storage.stats(str(request.get("period", "week")))
            summary = self.downloads.summary(); result["downloadsBytes"] = summary.get("used", 0)
            result["downloadsCount"] = len([row for row in summary.get("items", []) if row.get("state") == "done"])
            return result
        if command == "sessions": return {"items": self.storage.sessions(), "restoreQueue": self.preferences.get("restoreQueue", True)}
        if command == "session_save":
            media = [row["media"] for row in self.player.queue]
            result = self.storage.save_session(request.get("name"), media); self._collection_changed()
            return result
        if command == "session_delete":
            self.storage.delete_session(str(request.get("id", ""))); self._collection_changed()
            return {"items": self.storage.sessions()}
        if command == "session_restore":
            media = self.storage.session_media(str(request.get("id", "")))
            if request.get("mode") == "append":
                for item in media: self.player.enqueue(item, "end", lane=self.player.lane)
                return self.player.status()
            await self.player.replace_many(media)
            return self.player.status()
        if command == "home": return await self._home()
        if command == "history_clear":
            self.storage.clear_history()
            self._collection_changed()
            return {"cleared": True}
        if command == "playlist_create":
            result = self.storage.create_playlist(request.get("name"))
            self._collection_changed()
            return result
        if command == "playlist_rename":
            result = self.storage.rename_playlist(
                str(request.get("playlistId", "")),
                request.get("name"),
            )
            self._collection_changed()
            return result
        if command == "playlist_delete":
            self.storage.delete_playlist(str(request.get("playlistId", "")))
            self._collection_changed()
            return {"deleted": True}
        if command == "playlist_add":
            result = self.storage.add_playlist_item(
                str(request.get("playlistId", "")),
                self._media(request.get("media")),
            )
            self._collection_changed()
            return result
        if command == "comments":
            video_id = str(request.get("videoId", "")); cursor = request.get("cursor")
            return await self.catalog.request("comments", {"videoId": video_id, **({"cursor": str(cursor)} if cursor else {})}, timeout=30)
        if command == "watch_later":
            media = self._media(request.get("media"))
            playlist_id = self.storage.playlist_id_by_name("Смотреть позже") or self.storage.create_playlist("Смотреть позже")["id"]
            if playlist_id in self.storage.playlist_membership(media["videoId"]): return {"added": False, "playlistId": playlist_id}
            self.storage.add_playlist_item(playlist_id, media); self._collection_changed()
            return {"added": True, "playlistId": playlist_id}
        if command == "radio":
            video_id = str(request.get("videoId", ""))
            page = await self.catalog.request("related", {"videoId": video_id}, timeout=30)
            related = [row for row in page.get("items", []) if row.get("videoId")][:25]
            if not related: raise OmaTubeError("not_found", "Для этого видео нет похожих")
            self._hide_blocked(holder := {"items": related})
            seed = next((row["media"] for row in self.player.queue if row["media"].get("videoId") == video_id), None) or \
                {"videoId": video_id, "source": "youtube", "title": video_id, "author": "", "canonicalUrl": f"https://www.youtube.com/watch?v={video_id}"}
            await self.player.replace_many([seed, *holder["items"]])
            return self.player.status()
        if command == "hide_channel":
            self.storage.hide_channel(str(request.get("channelId", "")), str(request.get("title", ""))); self._collection_changed()
            return {"hidden": self.storage.hidden_channels()}
        if command == "unhide_channel":
            channel_id = request.get("channelId"); self.storage.unhide_channel(str(channel_id) if channel_id else None); self._collection_changed()
            return {"hidden": self.storage.hidden_channels()}
        if command == "hidden_channels": return {"hidden": self.storage.hidden_channels()}
        if command == "prefetch":
            video_id = str(request.get("videoId", ""))
            if video_id and self.preferences.get("hoverPrefetch", True): self.resolver.prefetch(video_id)
            return {"queued": bool(video_id)}
        if command == "downloads": return self.downloads.summary()
        if command == "download_add":
            kind = str(request.get("kind") or self.preferences["downloadKind"])
            return self.downloads.add(self._media(request.get("media")), kind)
        if command in {"download_pause", "download_resume", "download_retry"}:
            getattr(self.downloads, command.split("_", 1)[1])(str(request.get("id", ""))); return self.downloads.summary()
        if command in {"download_pause_all", "download_resume_all"}:
            getattr(self.downloads, command.split("_", 1)[1] + "_all")(); return self.downloads.summary()
        if command == "download_cancel":
            await self.downloads.cancel(str(request.get("id", ""))); return self.downloads.summary()
        if command == "download_remove":
            await self.downloads.remove(str(request.get("id", "")), bool(request.get("deleteFile"))); return self.downloads.summary()
        if command == "lyrics":
            return await self.lyrics_service.lookup(str(request.get("title", "")), str(request.get("author", "")),
                                                    float(request["duration"]) if isinstance(request.get("duration"), (int, float)) else None)
        if command == "subscribe":
            channel = request.get("channel")
            if not isinstance(channel, dict): raise OmaTubeError("invalid_request", "Некорректный канал")
            self.storage.subscribe(channel); self._collection_changed()
            self._background(self._sync_channel(str(channel["id"]), True))
            return {"subscribed": True}
        if command == "subscriptions_import":
            if not self.youtube_auth.status().get("authenticated"):
                raise OmaTubeError("auth_required", "Для импорта подписок войдите в аккаунт YouTube в настройках")
            channels = await fetch_channels(self.python, self.youtube_auth.path, self.proxy)
            fresh = [channel for channel in channels if not self.storage.is_subscribed(channel["id"])]
            for channel in fresh: self.storage.subscribe(channel)
            if fresh:
                self._collection_changed()
                self._background(self._sync_new_channels([channel["id"] for channel in fresh]))
            return {"imported": len(fresh), "total": len(channels)}
        if command == "unsubscribe":
            self.storage.unsubscribe(str(request.get("channelId", ""))); self._collection_changed()
            return {"subscribed": False}
        if command == "subscriptions":
            return {"items": self.storage.subscriptions(), "lastChecked": self.storage.last_checked()}
        if command == "is_subscribed":
            return {"subscribed": self.storage.is_subscribed(str(request.get("channelId", "")))}
        if command == "feed":
            return self.storage.feed(int(request.get("offset", 0)))
        if command == "feed_mark_seen":
            self.storage.mark_feed_seen(); self._collection_changed(); return {"newCount": 0}
        if command == "feed_refresh":
            added = await self._refresh_feed(); return {"added": added, "newCount": self.storage.new_count()}
        if command == "progress":
            ids = [str(value) for value in request.get("videoIds", []) if isinstance(value, str)]
            return {"progress": self.storage.progress_for(ids)}
        if command == "playlist_membership":
            video_id = str(request.get("videoId", ""))
            if not video_id: raise OmaTubeError("invalid_request", "Не указано видео")
            return {"playlistIds": self.storage.playlist_membership(video_id)}
        if command == "playlist_toggle":
            playlist_id = str(request.get("playlistId", "")); media = self._media(request.get("media"))
            if request.get("present"):
                self.storage.remove_playlist_video(playlist_id, media["videoId"]); present = False
            else:
                self.storage.add_playlist_item(playlist_id, media); present = True
            self._collection_changed()
            return {"present": present}
        if command == "playlist_remove":
            self.storage.remove_playlist_item(
                str(request.get("playlistId", "")),
                str(request.get("entryId", "")),
            )
            self._collection_changed()
            return {"removed": True}
        if command == "playlist_move":
            self.storage.move_playlist_item(
                str(request.get("playlistId", "")),
                str(request.get("entryId", "")),
                request.get("beforeEntryId"),
            )
            self._collection_changed()
            return {"moved": True}
        if command == "open_playlist":
            return self.storage.open_playlist(
                str(request.get("playlistId", "")),
                int(request.get("offset", 0)),
            )
        if command == "playlist_more":
            return self.storage.open_playlist(
                str(request.get("playlistId", "")),
                int(request.get("offset", 0)),
            )
        if command == "play_playlist":
            return await self._play_playlist(str(request.get("playlistId", "")), request.get("entryId"), request.get("resume") is True)
        if command == "playlist_copy": return self._operation(command, request, lambda: self._copy_playlist(request))
        if command == "operation_cancel": return await self._cancel(str(request.get("operationId", "")))
        if command == "setting": return await self._setting(request.get("key"), request.get("value"))
        raise OmaTubeError("invalid_request", "Неизвестная команда")

    @staticmethod
    def _start(value: Any, fallback: float | None) -> float:
        if value is None: return fallback or 0.0
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not 0 <= value <= MAX_START:
            raise OmaTubeError("invalid_request", "Некорректная позиция старта")
        return float(value)

    @staticmethod
    def _media_hints(value: Any) -> dict[str, Any]:
        """Display metadata sent along with a URL (browser extension); the resolver overwrites it on load."""
        if not isinstance(value, dict): return {}
        hints: dict[str, Any] = {}
        for key, limit in MEDIA_HINT_LIMITS.items():
            text = value.get(key)
            if isinstance(text, str) and text.strip(): hints[key] = text.strip()[:limit]
        duration = value.get("duration")
        if not isinstance(duration, bool) and isinstance(duration, (int, float)) and 0 < duration <= 7 * 24 * 3600:
            hints["duration"] = float(duration)
        return hints

    async def _search(self, request: dict[str, Any]) -> dict[str, Any]:
        source = str(request.get("source")); kind = str(request.get("kind", "all")); query = str(request.get("query", "")).strip()
        result = await self.catalog.request("search", {"source": source, "kind": kind, "query": query})
        self._decorate(result)
        view_id = str(uuid4()); self.views[view_id] = {"viewId": view_id, "type": "search", "source": source, "kind": kind, "query": query, **result}
        self._remember_search(query)
        return self.views[view_id]

    # Empty search opens on these; nothing is kept while history is off.
    def _remember_search(self, query: str) -> None:
        if not query or not self.preferences["historyEnabled"]: return
        stored = self.preferences["recentSearches"] if isinstance(self.preferences["recentSearches"], list) else []
        recent = [item for item in stored if isinstance(item, str) and item.casefold() != query.casefold()]
        self.preferences["recentSearches"] = [query[:200], *recent][:RECENT_SEARCHES]; self._save_preferences()

    def _background(self, coroutine) -> None:
        task = asyncio.ensure_future(coroutine); self.maintenance_tasks.add(task)
        task.add_done_callback(self.maintenance_tasks.discard)

    def _hide_blocked(self, result: dict[str, Any]) -> None:
        blocked = {row["id"] for row in self.storage.hidden_channels()}
        if not blocked: return
        keep = lambda item: not (isinstance(item, dict) and (item.get("authorId") in blocked or (item.get("kind") == "channel" and item.get("id") in blocked)))
        if isinstance(result.get("items"), list): result["items"] = [item for item in result["items"] if keep(item)]
        for section in (result.get("sections") or {}).values():
            if isinstance(section.get("items"), list): section["items"] = [item for item in section["items"] if keep(item)]

    def _decorate(self, result: dict[str, Any]) -> dict[str, Any]:
        self._hide_blocked(result)
        groups = [result.get("items") or []] + [section.get("items") or [] for section in (result.get("sections") or {}).values()]
        ids = [item["videoId"] for group in groups for item in group if isinstance(item, dict) and item.get("videoId")]
        progress = self.storage.progress_for(ids)
        if progress:
            for group in groups:
                for item in group:
                    if isinstance(item, dict) and item.get("videoId") in progress: item["watchProgress"] = progress[item["videoId"]]
        return result

    async def _home(self) -> dict[str, Any]:
        recommended: list[dict[str, Any]] = []
        seeds = self.storage.recent_video_ids(3)
        cached = getattr(self, "_home_cache", None)
        if seeds and not (cached and cached[0] == seeds[0] and time.time() - cached[1] < 1800):
            try:
                page = await self.catalog.request("related", {"videoId": seeds[0]}, timeout=30)
                self._home_cache = (seeds[0], time.time(), [row for row in page.get("items", []) if row.get("videoId")])
            except OmaTubeError:
                self._home_cache = (seeds[0], time.time() - 1500, [])
        if seeds and getattr(self, "_home_cache", None):
            watched = self.storage.watched_ids()
            recommended = [dict(row) for row in self._home_cache[2] if row["videoId"] not in watched and row["videoId"] != seeds[0]][:8]
        result = {"continue": self.storage.continue_watching(4), "new": self.storage.feed(0, 4)["items"], "recommended": recommended,
                  "newCount": self.storage.new_count(), "seed": seeds[0] if seeds else None}
        for key in ("continue", "new", "recommended"):
            holder = {"items": result[key]}; self._decorate(holder); result[key] = holder["items"]
        return result

    async def _sync_channel(self, channel_id: str, initial: bool = False) -> int:
        parsed = await self.feed_service.fetch(channel_id)
        if not parsed or not self.storage.is_subscribed(channel_id): return 0
        added = self.storage.add_feed_items(channel_id, parsed["items"], initial)
        if added: self._collection_changed()
        return 0 if initial else added

    async def _sync_new_channels(self, channel_ids: list[str]) -> None:
        await asyncio.gather(*(self._sync_channel(channel_id, True) for channel_id in channel_ids), return_exceptions=True)

    async def _refresh_feed(self) -> int:
        results = await asyncio.gather(*(self._sync_channel(channel_id) for channel_id in self.storage.subscription_ids()), return_exceptions=True)
        return sum(value for value in results if isinstance(value, int))

    async def _feed_loop(self) -> None:
        await asyncio.sleep(20)
        while True:
            try: await self._refresh_feed()
            except Exception: pass
            await asyncio.sleep(1800)

    async def _open_entity(self, entity: Any) -> dict[str, Any]:
        if not isinstance(entity, dict): raise OmaTubeError("invalid_request", "Некорректная сущность каталога")
        result = await self.catalog.request("open", {"entity": entity})
        if entity.get("kind") == "channel":
            header = result.get("entity") if isinstance(result.get("entity"), dict) else {}
            result["entity"] = {**entity, **{key: value for key, value in header.items() if value not in (None, "")}, "id": entity.get("id"), "kind": "channel", "source": entity.get("source", "youtube")}
            result["subscribed"] = self.storage.is_subscribed(str(entity.get("id")))
        self._decorate(result)
        view_id = str(uuid4()); self.views[view_id] = {"viewId": view_id, "type": "entity", **result}; return self.views[view_id]

    async def _entity_section(self, view_id: str, tab: str, sort: str | None) -> dict[str, Any]:
        view = self.views.get(view_id)
        entity = view.get("entity") if view else None
        if not view or not isinstance(entity, dict) or entity.get("kind") != "channel": raise OmaTubeError("not_found", "Страница канала не найдена")
        section = await self.catalog.request("channel_section", {"channelId": entity.get("id"), "tab": tab, **({"sort": sort} if sort else {})})
        self._decorate(section)
        view.setdefault("sections", {})[tab] = section
        view["sort"] = sort
        return view

    async def _more(self, view_id: str) -> dict[str, Any]:
        view = self.views.get(view_id)
        if not view: raise OmaTubeError("not_found", "Страница не найдена")
        target = view
        if view.get("sections"):
            target = next((section for section in view["sections"].values() if section.get("nextCursor")), None)
            if target is None: return view
        cursor = target.get("nextCursor")
        if not cursor: return view
        page = await self.catalog.request("next", {"cursor": cursor})
        target["items"] = [*target.get("items", []), *page.get("items", [])]
        target["nextCursor"] = page.get("nextCursor"); target["exhausted"] = page.get("exhausted", True)
        return view

    async def _play_view(self, view_id: str, selected: Any) -> dict[str, Any]:
        view = self.views.get(view_id)
        if not view: raise OmaTubeError("not_found", "Страница не найдена")
        source_rows = view.get("items", [])
        if view.get("sections"):
            source_rows = [item for section in view["sections"].values() for item in section.get("items", [])]
        rows = [item for item in source_rows if item.get("videoId")]
        if not rows: raise OmaTubeError("not_found", "На странице нет доступных медиа")
        index = next((i for i, row in enumerate(rows) if selected in {row.get("entryId"), row.get("videoId")}), 0)
        await self.player.replace_many(rows[index:])
        return self.player.status()

    async def _play_playlist(self, playlist_id: str, selected: Any, resume: bool = False) -> dict[str, Any]:
        playlist = self.storage.open_playlist(playlist_id, 0, 1000000); rows = playlist["items"]
        if not rows: raise OmaTubeError("not_found", "Плейлист пуст")
        index = 0 if selected is None else next((i for i, row in enumerate(rows) if row["entryId"] == selected), -1)
        if index < 0: raise OmaTubeError("not_found", "Элемент плейлиста не найден")
        start = 0.0
        saved = playlist.get("resume") if resume and selected is None else None
        if saved:
            # Prefer the remembered video over the remembered index: the list may have been reordered.
            found = next((i for i, row in enumerate(rows) if row["media"].get("videoId") == saved.get("videoId")), -1)
            index = found if found >= 0 else min(int(saved["index"]), len(rows) - 1)
            start = float(saved["position"]) if found >= 0 else 0.0
        context = {"kind": "playlist", "id": playlist_id, "name": playlist.get("name") or "", "offset": index, "total": len(rows)}
        await self.player.replace_many([row["media"] for row in rows[index:]], start, context)
        return self.player.status()

    async def _copy_playlist(self, request: dict[str, Any]) -> dict[str, Any]:
        entity = request.get("entity"); name = request.get("name")
        if not isinstance(entity, dict) or entity.get("kind") != "playlist": raise OmaTubeError("invalid_request", "Можно копировать только плейлист")
        operation_id = next((op_id for op_id, record in self.operations.items() if record.get("task") is asyncio.current_task()), str(uuid4()))
        processed = 0; skipped = 0; seen_cursors: set[str] = set()
        try:
            page = await self.catalog.request("open", {"entity": entity})
            while True:
                valid = [item for item in page.get("items", []) if item.get("videoId")]
                skipped += len(page.get("items", [])) - len(valid)
                self.storage.stage_copy_page(operation_id, valid, processed); processed += len(valid)
                record = self.operations.get(operation_id)
                if record:
                    record["processed"] = processed
                    self.catalog_revision += 1
                    self._changed()
                cursor = page.get("nextCursor")
                if not cursor: break
                if cursor in seen_cursors: raise OmaTubeError("provider_error", "Каталог повторил страницу плейлиста")
                seen_cursors.add(cursor); page = await self.catalog.request("next", {"cursor": cursor})
            result = self.storage.finish_copy(operation_id, name, {"entity": entity, "copiedAt": time.time(), "source": entity.get("source")})
            result["skipped"] = skipped
            self._collection_changed()
            return result
        except BaseException:
            self.storage.cancel_copy(operation_id); raise

    async def _cancel(self, operation_id: str) -> dict[str, Any]:
        record = self.operations.get(operation_id)
        if not record: raise OmaTubeError("not_found", "Операция не найдена")
        if record["state"] != "running": return {"cancelled": False, "state": record["state"]}
        record["task"].cancel(); await asyncio.gather(record["task"], return_exceptions=True)
        self.storage.cancel_copy(operation_id); return {"cancelled": True}

    async def _set_video_quality(self, value: int) -> dict[str, Any]:
        if self.preferences["videoQuality"] == value:
            return self.preferences
        self.preferences["videoQuality"] = value
        self.resolver.max_video_height = value
        self._save_preferences()
        if self.player.current and self.player.video_mode != "audio":
            await self.player.reload_current()
        return self.preferences


    async def _setting(self, key: Any, value: Any) -> dict[str, Any]:
        if key not in DEFAULT_PREFERENCES: raise OmaTubeError("invalid_request", "Неизвестная настройка")
        if key in {"showCover", "showAuthor", "showTitle", "showControls", "showProgress", "marquee", "historyEnabled", "onboarded", "normalize", "skipSilence", "hideWhenIdle", "wheelVolume", "hoverPrefetch", "restoreQueue", "browserAccept", "browserNotify"}:
            if not isinstance(value, bool): raise OmaTubeError("invalid_request", "Ожидается логическое значение")
        elif key == "sponsorActions":
            if (not isinstance(value, dict) or set(value) - set(SPONSOR_CATEGORIES)
                    or any(action not in SPONSOR_ACTIONS for action in value.values())):
                raise OmaTubeError("invalid_request", "Некорректные действия SponsorBlock")
            value = {**self.preferences["sponsorActions"], **value}
            self.player.sponsor_actions = value
        elif key in CHOICE_PREFERENCES:
            if value not in CHOICE_PREFERENCES[key]: raise OmaTubeError("invalid_request", "Недопустимое значение настройки")
        elif key == "recentSearches":
            if not isinstance(value, list) or len(value) > RECENT_SEARCHES or any(not isinstance(item, str) or len(item) > 200 for item in value):
                raise OmaTubeError("invalid_request", "Некорректный список запросов")
        elif key == "textWidth":
            if not isinstance(value, (int, float)) or not 80 <= value <= 600: raise OmaTubeError("invalid_request", "Ширина текста должна быть от 80 до 600")
            value = int(value)
        elif key == "videoQuality":
            if type(value) is not int or value not in VIDEO_QUALITIES:
                raise OmaTubeError("invalid_request", "Некорректное качество видео")
            return await self._set_video_quality(value)
        self.preferences[key] = value; self._save_preferences()
        if key == "historyEnabled": self.player.history_enabled = value
        if key in {"normalize", "skipSilence"}:
            await self.player.set_audio_options(self.preferences["normalize"], self.preferences["skipSilence"])
        return self.preferences

    async def handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            line = await reader.readline()
            if not line or len(line) > MAX_REQUEST: raise OmaTubeError("invalid_request", "Запрос превышает допустимый размер")
            try: request = json.loads(line)
            except json.JSONDecodeError as exc: raise OmaTubeError("invalid_request", "Некорректный JSON") from exc
            if not isinstance(request, dict): raise OmaTubeError("invalid_request", "Запрос должен быть объектом")
            result = await self.command(request); response = {"ok": True, "result": result}
        except OmaTubeError as error: response = {"ok": False, "error": error.as_dict()}
        except Exception:
            traceback.print_exc()
            response = {"ok": False, "error": {"code": "storage_error", "message": "Внутренняя ошибка backend"}}
        payload = json.dumps(response, ensure_ascii=False, separators=(",", ":")).encode() + b"\n"
        if len(payload) > MAX_RESPONSE: payload = b'{"ok":false,"error":{"code":"provider_error","message":"Response too large"}}\n'
        writer.write(payload); await writer.drain(); writer.close(); await writer.wait_closed()

    async def start(self) -> None:
        self.socket_path.unlink(missing_ok=True)
        self.server = await asyncio.start_unix_server(self.handle, self.socket_path)
        self.socket_path.chmod(0o600)
        self.mpris = MprisBridge(self.player, lambda: self.preferences.get("language")); await self.mpris.start()
        await self.image_server.start()
        self.catalog_warm_task = asyncio.create_task(self._warm_catalog())
        self._background(self._warm_network())
        self.feed_task = asyncio.create_task(self._feed_loop())

    async def _warm_network(self) -> None:
        # Open TLS connections and start the idle mpv process before the first click needs them.
        await asyncio.to_thread(self.http.warm)
        try:
            await self.mpv.start()
        except Exception:
            pass

    async def _warm_catalog(self) -> None:
        try:
            await self.catalog.request("ping", {}, timeout=30)
        except (OmaTubeError, asyncio.CancelledError):
            pass

    async def stop(self) -> None:
        await self.image_server.stop()
        operation_tasks = [
            task
            for record in self.operations.values()
            if (task := record.get("task")) and not task.done()
        ]
        for task in operation_tasks:
            task.cancel()
        if operation_tasks:
            await asyncio.gather(*operation_tasks, return_exceptions=True)
        if self.maintenance_tasks:
            await asyncio.gather(*tuple(self.maintenance_tasks), return_exceptions=True)
        if self.feed_task and not self.feed_task.done():
            self.feed_task.cancel(); await asyncio.gather(self.feed_task, return_exceptions=True)
        if self.catalog_warm_task and not self.catalog_warm_task.done():
            self.catalog_warm_task.cancel()
            await asyncio.gather(self.catalog_warm_task, return_exceptions=True)
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        self.socket_path.unlink(missing_ok=True)
        await self.downloads.shutdown()
        await self.player.shutdown()
        await self.catalog.stop()
        if self.mpris:
            self.mpris.stop()
        self.storage.close()


async def async_main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--app-root", type=Path, default=Path(__file__).resolve().parents[1]); args = parser.parse_args()
    backend = Backend(args.app_root); await backend.start()
    stop = asyncio.Event(); loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM): loop.add_signal_handler(sig, stop.set)
    try: await stop.wait()
    finally: await backend.stop()


def main() -> None:
    try: asyncio.run(async_main())
    except OmaTubeError as error: raise SystemExit(f"{error.code}: {error.message}")


if __name__ == "__main__": main()
