from __future__ import annotations

import json
from pathlib import Path
import sqlite3
import time
from typing import Any, Iterable
from uuid import uuid4

from .errors import OmaTubeError


class Storage:
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = path
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self._migrate()
        try:
            path.chmod(0o600)
        except FileNotFoundError:
            pass

    def close(self) -> None:
        self.db.close()

    def _migrate(self) -> None:
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version < 1:
            with self.db:
                self.db.execute("CREATE TABLE player_state(id INTEGER PRIMARY KEY CHECK(id=1), snapshot_json TEXT NOT NULL)")
                self.db.execute("PRAGMA user_version=1")
        if version < 2:
            with self.db:
                self.db.executescript("""
                    CREATE TABLE media(video_id TEXT PRIMARY KEY, metadata_json TEXT NOT NULL);
                    CREATE TABLE saved_media(video_id TEXT PRIMARY KEY REFERENCES media(video_id), saved_at REAL NOT NULL);
                    CREATE TABLE bookmarks(source TEXT NOT NULL, kind TEXT NOT NULL, entity_id TEXT NOT NULL,
                        metadata_json TEXT NOT NULL, saved_at REAL NOT NULL, PRIMARY KEY(source,kind,entity_id));
                    CREATE TABLE history(play_id TEXT PRIMARY KEY, video_id TEXT NOT NULL REFERENCES media(video_id),
                        source TEXT NOT NULL, started_at REAL NOT NULL);
                    PRAGMA user_version=2;
                """)
        if version < 3:
            with self.db:
                self.db.executescript("""
                    CREATE TABLE playlists(id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at REAL NOT NULL,
                        updated_at REAL NOT NULL, origin_json TEXT);
                    CREATE TABLE playlist_items(entry_id TEXT PRIMARY KEY,
                        playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
                        video_id TEXT NOT NULL REFERENCES media(video_id), source TEXT NOT NULL, position INTEGER NOT NULL,
                        UNIQUE(playlist_id,position));
                    PRAGMA user_version=3;
                """)
        self.db.execute("CREATE TEMP TABLE IF NOT EXISTS copy_staging(operation_id TEXT NOT NULL, ordinal INTEGER NOT NULL, media_json TEXT NOT NULL, PRIMARY KEY(operation_id,ordinal))")

    @staticmethod
    def _json(value: Any) -> str:
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))

    @staticmethod
    def _decode(row: sqlite3.Row | None, key: str) -> Any:
        return json.loads(row[key]) if row else None

    @staticmethod
    def _media_thumbnail(media: dict[str, Any]) -> str | None:
        video_id = media.get("videoId")
        if isinstance(video_id, str) and video_id and media.get("source") in {"youtube", "music"}:
            return f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
        thumbnail = media.get("thumbnailUrl")
        return thumbnail if isinstance(thumbnail, str) and thumbnail else None

    @staticmethod
    def _playlist_payload(row: sqlite3.Row) -> dict[str, Any]:
        result = dict(row)
        origin_raw = result.pop("origin_json", None)
        cover_raw = result.pop("cover_media_json", None)
        origin = json.loads(origin_raw) if origin_raw else None
        origin_entity = (origin or {}).get("entity") or origin or {}
        cover_media = json.loads(cover_raw) if cover_raw else {}
        item_count = int(result.pop("item_count", 0))
        result.update({
            "kind": "playlist",
            "source": "local",
            "title": result["name"],
            "author": f"{item_count} видео",
            "thumbnailUrl": origin_entity.get("thumbnailUrl") or Storage._media_thumbnail(cover_media),
            "itemCount": item_count,
        })
        if origin:
            result["origin"] = origin
        return result

    def load_player_state(self) -> dict[str, Any] | None:
        row = self.db.execute("SELECT snapshot_json FROM player_state WHERE id=1").fetchone()
        if not row:
            return None
        try:
            value = json.loads(row[0])
        except json.JSONDecodeError as exc:
            raise OmaTubeError("storage_error", "Сохранённое состояние плеера повреждено") from exc
        if not isinstance(value, dict):
            raise OmaTubeError("storage_error", "Сохранённое состояние плеера повреждено")
        return value

    def save_player_state(self, snapshot: dict[str, Any]) -> None:
        with self.db:
            self.db.execute("INSERT INTO player_state(id,snapshot_json) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET snapshot_json=excluded.snapshot_json", (self._json(snapshot),))

    def upsert_media(self, media: dict[str, Any]) -> None:
        video_id = media.get("videoId")
        if not isinstance(video_id, str) or not video_id:
            raise OmaTubeError("invalid_request", "У медиа отсутствует videoId")
        with self.db:
            self.db.execute("INSERT INTO media(video_id,metadata_json) VALUES(?,?) ON CONFLICT(video_id) DO UPDATE SET metadata_json=excluded.metadata_json", (video_id, self._json(media)))

    def save_media(self, media: dict[str, Any], saved: bool) -> None:
        self.upsert_media(media)
        with self.db:
            if saved:
                self.db.execute("INSERT INTO saved_media(video_id,saved_at) VALUES(?,?) ON CONFLICT(video_id) DO NOTHING", (media["videoId"], time.time()))
            else:
                self.db.execute("DELETE FROM saved_media WHERE video_id=?", (media["videoId"],))

    def save_entity(self, entity: dict[str, Any], saved: bool) -> None:
        key = (entity.get("source"), entity.get("kind"), entity.get("id"))
        if not all(isinstance(value, str) and value for value in key):
            raise OmaTubeError("invalid_request", "Некорректная сущность каталога")
        with self.db:
            if saved:
                self.db.execute("INSERT INTO bookmarks(source,kind,entity_id,metadata_json,saved_at) VALUES(?,?,?,?,?) ON CONFLICT(source,kind,entity_id) DO UPDATE SET metadata_json=excluded.metadata_json", (*key, self._json(entity), time.time()))
            else:
                self.db.execute("DELETE FROM bookmarks WHERE source=? AND kind=? AND entity_id=?", key)

    def add_history(self, media: dict[str, Any], play_id: str | None = None) -> str:
        self.upsert_media(media)
        play_id = play_id or str(uuid4())
        with self.db:
            self.db.execute("INSERT INTO history(play_id,video_id,source,started_at) VALUES(?,?,?,?)", (play_id, media["videoId"], media.get("source", "youtube"), time.time()))
        return play_id

    def clear_history(self) -> None:
        with self.db:
            self.db.execute("DELETE FROM history")

    def collection(self, section: str, offset: int = 0, limit: int = 50) -> dict[str, Any]:
        offset = max(0, int(offset)); limit = min(50, max(1, int(limit)))
        if section == "saved":
            rows = self.db.execute("SELECT m.metadata_json FROM saved_media s JOIN media m USING(video_id) ORDER BY s.saved_at DESC LIMIT ? OFFSET ?", (limit + 1, offset)).fetchall()
            items = [json.loads(row[0]) for row in rows[:limit]]
        elif section in {"bookmarks", "authors"}:
            condition = "kind IN ('channel','artist')" if section == "authors" else "kind='playlist'"
            rows = self.db.execute(f"SELECT metadata_json FROM bookmarks WHERE {condition} ORDER BY saved_at DESC LIMIT ? OFFSET ?", (limit + 1, offset)).fetchall()
            items = [json.loads(row[0]) for row in rows[:limit]]
        elif section == "history":
            rows = self.db.execute("SELECT h.play_id,h.started_at,m.metadata_json FROM history h JOIN media m USING(video_id) ORDER BY h.started_at DESC LIMIT ? OFFSET ?", (limit + 1, offset)).fetchall()
            items = [{**json.loads(row["metadata_json"]), "playId": row["play_id"], "startedAt": row["started_at"]} for row in rows[:limit]]
        elif section == "playlists":
            rows = self.db.execute("""
                SELECT p.id,p.name,p.created_at,p.updated_at,p.origin_json,
                    (SELECT COUNT(*) FROM playlist_items pi WHERE pi.playlist_id=p.id) AS item_count,
                    (SELECT m.metadata_json FROM playlist_items pi JOIN media m USING(video_id)
                     WHERE pi.playlist_id=p.id ORDER BY pi.position LIMIT 1) AS cover_media_json
                FROM playlists p ORDER BY p.updated_at DESC LIMIT ? OFFSET ?
            """, (limit + 1, offset)).fetchall()
            items = [self._playlist_payload(row) for row in rows[:limit]]
        else:
            raise OmaTubeError("invalid_request", "Неизвестный раздел коллекции")
        return {"items": items, "offset": offset, "nextOffset": offset + limit if len(rows) > limit else None}

    @staticmethod
    def _playlist_name(name: Any) -> str:
        value = str(name).strip()
        if not 1 <= len(value) <= 200:
            raise OmaTubeError("invalid_request", "Название плейлиста должно содержать от 1 до 200 символов")
        return value

    def create_playlist(self, name: Any, origin: dict[str, Any] | None = None, playlist_id: str | None = None) -> dict[str, Any]:
        now = time.time(); playlist_id = playlist_id or str(uuid4())
        with self.db:
            self.db.execute("INSERT INTO playlists(id,name,created_at,updated_at,origin_json) VALUES(?,?,?,?,?)", (playlist_id, self._playlist_name(name), now, now, self._json(origin) if origin else None))
        return self.open_playlist(playlist_id)

    def rename_playlist(self, playlist_id: str, name: Any) -> dict[str, Any]:
        with self.db:
            cursor = self.db.execute("UPDATE playlists SET name=?,updated_at=? WHERE id=?", (self._playlist_name(name), time.time(), playlist_id))
            if cursor.rowcount != 1: raise OmaTubeError("not_found", "Плейлист не найден")
        return self.open_playlist(playlist_id)

    def delete_playlist(self, playlist_id: str) -> None:
        with self.db:
            cursor = self.db.execute("DELETE FROM playlists WHERE id=?", (playlist_id,))
            if cursor.rowcount != 1: raise OmaTubeError("not_found", "Плейлист не найден")

    def _require_playlist(self, playlist_id: str) -> None:
        if not self.db.execute("SELECT 1 FROM playlists WHERE id=?", (playlist_id,)).fetchone():
            raise OmaTubeError("not_found", "Плейлист не найден")

    def add_playlist_item(self, playlist_id: str, media: dict[str, Any]) -> dict[str, Any]:
        self._require_playlist(playlist_id); self.upsert_media(media)
        entry_id = str(uuid4())
        with self.db:
            position = self.db.execute("SELECT COALESCE(MAX(position)+1,0) FROM playlist_items WHERE playlist_id=?", (playlist_id,)).fetchone()[0]
            self.db.execute("INSERT INTO playlist_items(entry_id,playlist_id,video_id,source,position) VALUES(?,?,?,?,?)", (entry_id, playlist_id, media["videoId"], media.get("source", "youtube"), position))
            self.db.execute("UPDATE playlists SET updated_at=? WHERE id=?", (time.time(), playlist_id))
        return {"entryId": entry_id, "media": media}

    def remove_playlist_item(self, playlist_id: str, entry_id: str) -> None:
        with self.db:
            row = self.db.execute("SELECT position FROM playlist_items WHERE playlist_id=? AND entry_id=?", (playlist_id, entry_id)).fetchone()
            if not row: raise OmaTubeError("not_found", "Элемент плейлиста не найден")
            self.db.execute("DELETE FROM playlist_items WHERE entry_id=?", (entry_id,))
            self.db.execute("UPDATE playlist_items SET position=position-1 WHERE playlist_id=? AND position>?", (playlist_id, row[0]))
            self.db.execute("UPDATE playlists SET updated_at=? WHERE id=?", (time.time(), playlist_id))

    def move_playlist_item(self, playlist_id: str, entry_id: str, before_entry_id: str | None) -> None:
        rows = self.db.execute("SELECT entry_id FROM playlist_items WHERE playlist_id=? ORDER BY position", (playlist_id,)).fetchall()
        ids = [row[0] for row in rows]
        if entry_id not in ids or (before_entry_id is not None and before_entry_id not in ids):
            raise OmaTubeError("not_found", "Элемент плейлиста не найден")
        ids.remove(entry_id)
        ids.insert(ids.index(before_entry_id) if before_entry_id else len(ids), entry_id)
        with self.db:
            for position, item_id in enumerate(ids):
                self.db.execute("UPDATE playlist_items SET position=? WHERE entry_id=?", (-position - 1, item_id))
            self.db.execute("UPDATE playlist_items SET position=-position-1 WHERE playlist_id=?", (playlist_id,))
            self.db.execute("UPDATE playlists SET updated_at=? WHERE id=?", (time.time(), playlist_id))

    def open_playlist(self, playlist_id: str, offset: int = 0, limit: int = 50) -> dict[str, Any]:
        playlist = self.db.execute("""
            SELECT p.id,p.name,p.created_at,p.updated_at,p.origin_json,
                (SELECT COUNT(*) FROM playlist_items pi WHERE pi.playlist_id=p.id) AS item_count,
                (SELECT m.metadata_json FROM playlist_items pi JOIN media m USING(video_id)
                 WHERE pi.playlist_id=p.id ORDER BY pi.position LIMIT 1) AS cover_media_json
            FROM playlists p WHERE p.id=?
        """, (playlist_id,)).fetchone()
        if not playlist:
            raise OmaTubeError("not_found", "Плейлист не найден")
        rows = self.db.execute(
            "SELECT p.entry_id,p.source,m.metadata_json FROM playlist_items p "
            "JOIN media m USING(video_id) WHERE p.playlist_id=? ORDER BY p.position LIMIT ? OFFSET ?",
            (playlist_id, limit + 1, offset),
        ).fetchall()
        items = []
        for row in rows[:limit]:
            media = json.loads(row["metadata_json"])
            media["thumbnailUrl"] = self._media_thumbnail(media)
            items.append({"entryId": row["entry_id"], "media": media})
        result = self._playlist_payload(playlist)
        result["items"] = items
        result["nextOffset"] = offset + limit if len(rows) > limit else None
        return result

    def stage_copy_page(self, operation_id: str, items: Iterable[dict[str, Any]], start: int) -> int:
        rows = [(operation_id, start + index, self._json(item)) for index, item in enumerate(items)]
        with self.db:
            self.db.executemany("INSERT INTO copy_staging(operation_id,ordinal,media_json) VALUES(?,?,?)", rows)
        return len(rows)

    def cancel_copy(self, operation_id: str) -> None:
        with self.db: self.db.execute("DELETE FROM copy_staging WHERE operation_id=?", (operation_id,))

    def finish_copy(self, operation_id: str, name: Any, origin: dict[str, Any]) -> dict[str, Any]:
        playlist_id = str(uuid4()); now = time.time()
        rows = self.db.execute("SELECT media_json FROM copy_staging WHERE operation_id=? ORDER BY ordinal", (operation_id,)).fetchall()
        with self.db:
            self.db.execute("INSERT INTO playlists(id,name,created_at,updated_at,origin_json) VALUES(?,?,?,?,?)", (playlist_id, self._playlist_name(name), now, now, self._json(origin)))
            position = 0
            for row in rows:
                media = json.loads(row[0]); video_id = media.get("videoId")
                if not video_id: continue
                self.db.execute("INSERT INTO media(video_id,metadata_json) VALUES(?,?) ON CONFLICT(video_id) DO UPDATE SET metadata_json=excluded.metadata_json", (video_id, self._json(media)))
                self.db.execute("INSERT INTO playlist_items(entry_id,playlist_id,video_id,source,position) VALUES(?,?,?,?,?)", (str(uuid4()), playlist_id, video_id, media.get("source", "youtube"), position)); position += 1
            self.db.execute("DELETE FROM copy_staging WHERE operation_id=?", (operation_id,))
        return self.open_playlist(playlist_id)
