from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
import signal
import time
from typing import Any, Awaitable, Callable
from uuid import uuid4

from .catalog import CatalogBridge
from .errors import OmaTubeError
from .mpris import MprisBridge
from .mpv import MpvController
from .player import Player
from .resolver import AudioResolver
from .storage import Storage
from .urls import normalize_youtube_url

MAX_REQUEST = 64 * 1024
MAX_RESPONSE = 8 * 1024 * 1024
DEFAULT_PREFERENCES = {
    "showCover": True, "showAuthor": True, "showTitle": True, "showControls": True,
    "showProgress": True, "textWidth": 220, "marquee": False, "historyEnabled": True,
}
VIEW_OPERATION_KINDS = {
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
        self.storage = Storage(data_home / "library.sqlite3")
        proxy = os.environ.get("OMATUBE_PROXY") or os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
        self.catalog = CatalogBridge(app_root / "catalog/worker.mjs", proxy=proxy)
        python = app_root / ".venv/bin/python"
        if not python.exists(): python = Path(os.environ.get("OMATUBE_PYTHON", os.sys.executable))
        self.resolver = AudioResolver(python, proxy=proxy)
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
        )
        self.player.history_enabled = bool(self.preferences["historyEnabled"])
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
            "preferences": self.preferences,
        }

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
                    "message": "Операция каталога завершилась ошибкой",
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
            normalized = normalize_youtube_url(request.get("url", ""))
            if normalized["kind"] == "playlist":
                entity = {"source": "youtube", "kind": "playlist", "id": normalized["id"], "title": "Плейлист YouTube", "author": "", "thumbnailUrl": None, "canonicalUrl": normalized["canonicalUrl"]}
                return self._operation(command, request, lambda: self._open_entity(entity))
            media = {"videoId": normalized["videoId"], "source": "youtube", "title": normalized["videoId"],
                     "author": "Автор неизвестен", "authorId": None, "duration": None, "thumbnailUrl": None,
                     "canonicalUrl": normalized["canonicalUrl"]}
            if command == "play_url": return await self.player.replace(media)
            return self.player.enqueue(media, request.get("placement", "end"))
        if command in {"play", "pause", "toggle_pause", "next", "previous", "queue_clear"}:
            if command == "play": await self.player.play()
            elif command == "pause": await self.player.pause()
            elif command == "toggle_pause": await (self.player.pause() if self.player.state == "playing" else self.player.play())
            elif command == "next": await self.player.next(True)
            elif command == "previous": await self.player.previous()
            else: await self.player.clear()
            return self.player.status()
        if command == "seek": await self.player.seek(float(request.get("seconds", 0))); return self.player.status()
        if command == "volume":
            value = float(request.get("value", -1))
            if not 0 <= value <= 100: raise OmaTubeError("invalid_request", "Громкость должна быть от 0 до 100")
            self.player.volume = value; await self.mpv.set_volume(value); self.player.persist(); self._changed(); return self.player.status()
        if command == "mute":
            value = request.get("value")
            if not isinstance(value, bool): raise OmaTubeError("invalid_request", "Некорректное значение mute")
            self.player.muted = value; await self.mpv.set_mute(value); self.player.persist(); self._changed(); return self.player.status()
        if command == "queue_play": await self.player.play_entry(str(request.get("entryId", ""))); return self.player.status()
        if command == "queue_remove": await self.player.remove(str(request.get("entryId", ""))); return self.player.status()
        if command == "queue_move": self.player.move(str(request.get("entryId", "")), request.get("beforeEntryId")); return self.player.status()
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
        if command == "save_entity":
            saved = bool(request.get("saved"))
            self.storage.save_entity(request.get("entity"), saved)
            self._collection_changed()
            return {"saved": saved}
        if command == "collection":
            return self.storage.collection(
                str(request.get("section")),
                int(request.get("offset", 0)),
            )
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
        if command == "play_playlist": return await self._play_playlist(str(request.get("playlistId", "")), request.get("entryId"))
        if command == "playlist_copy": return self._operation(command, request, lambda: self._copy_playlist(request))
        if command == "operation_cancel": return await self._cancel(str(request.get("operationId", "")))
        if command == "setting": return await self._setting(request.get("key"), request.get("value"))
        raise OmaTubeError("invalid_request", "Неизвестная команда")

    async def _search(self, request: dict[str, Any]) -> dict[str, Any]:
        source = str(request.get("source")); kind = str(request.get("kind", "all")); query = str(request.get("query", "")).strip()
        result = await self.catalog.request("search", {"source": source, "kind": kind, "query": query})
        view_id = str(uuid4()); self.views[view_id] = {"viewId": view_id, "type": "search", "source": source, "kind": kind, "query": query, **result}
        return self.views[view_id]

    async def _open_entity(self, entity: Any) -> dict[str, Any]:
        if not isinstance(entity, dict): raise OmaTubeError("invalid_request", "Некорректная сущность каталога")
        result = await self.catalog.request("open", {"entity": entity})
        view_id = str(uuid4()); self.views[view_id] = {"viewId": view_id, "type": "entity", **result}; return self.views[view_id]

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

    async def _play_playlist(self, playlist_id: str, selected: Any) -> dict[str, Any]:
        playlist = self.storage.open_playlist(playlist_id, 0, 1000000); rows = playlist["items"]
        if not rows: raise OmaTubeError("not_found", "Плейлист пуст")
        index = 0 if selected is None else next((i for i, row in enumerate(rows) if row["entryId"] == selected), -1)
        if index < 0: raise OmaTubeError("not_found", "Элемент плейлиста не найден")
        await self.player.replace_many([
            row["media"] for row in rows[index:]
        ])
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

    async def _setting(self, key: Any, value: Any) -> dict[str, Any]:
        if key not in DEFAULT_PREFERENCES: raise OmaTubeError("invalid_request", "Неизвестная настройка")
        if key in {"showCover", "showAuthor", "showTitle", "showControls", "showProgress", "marquee", "historyEnabled"}:
            if not isinstance(value, bool): raise OmaTubeError("invalid_request", "Ожидается логическое значение")
        elif key == "textWidth":
            if not isinstance(value, (int, float)) or not 80 <= value <= 600: raise OmaTubeError("invalid_request", "Ширина текста должна быть от 80 до 600")
            value = int(value)
        self.preferences[key] = value; self._save_preferences()
        if key == "historyEnabled": self.player.history_enabled = value
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
        except Exception: response = {"ok": False, "error": {"code": "storage_error", "message": "Внутренняя ошибка backend"}}
        payload = json.dumps(response, ensure_ascii=False, separators=(",", ":")).encode() + b"\n"
        if len(payload) > MAX_RESPONSE: payload = b'{"ok":false,"error":{"code":"provider_error","message":"Response too large"}}\n'
        writer.write(payload); await writer.drain(); writer.close(); await writer.wait_closed()

    async def start(self) -> None:
        self.socket_path.unlink(missing_ok=True)
        self.server = await asyncio.start_unix_server(self.handle, self.socket_path)
        self.socket_path.chmod(0o600)
        self.mpris = MprisBridge(self.player); await self.mpris.start()
        self.catalog_warm_task = asyncio.create_task(self._warm_catalog())

    async def _warm_catalog(self) -> None:
        try:
            await self.catalog.request("ping", {}, timeout=30)
        except (OmaTubeError, asyncio.CancelledError):
            pass

    async def stop(self) -> None:
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
        if self.catalog_warm_task and not self.catalog_warm_task.done():
            self.catalog_warm_task.cancel()
            await asyncio.gather(self.catalog_warm_task, return_exceptions=True)
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        self.socket_path.unlink(missing_ok=True)
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
