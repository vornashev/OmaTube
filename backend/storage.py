from __future__ import annotations

import json
from datetime import date, datetime, timedelta
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
        if version < 4:
            with self.db:
                self.db.executescript("""
                    CREATE TABLE subscriptions(channel_id TEXT PRIMARY KEY, title TEXT NOT NULL, thumbnail_url TEXT,
                        metadata_json TEXT NOT NULL, subscribed_at REAL NOT NULL, checked_at REAL);
                    CREATE TABLE feed_items(video_id TEXT PRIMARY KEY REFERENCES media(video_id),
                        channel_id TEXT NOT NULL REFERENCES subscriptions(channel_id) ON DELETE CASCADE,
                        published_at REAL NOT NULL, seen INTEGER NOT NULL DEFAULT 0);
                    CREATE INDEX feed_items_published ON feed_items(published_at DESC);
                    CREATE TABLE watch_progress(video_id TEXT PRIMARY KEY, position REAL NOT NULL, duration REAL NOT NULL,
                        updated_at REAL NOT NULL);
                    PRAGMA user_version=4;
                """)
        if version < 5:
            with self.db:
                self.db.executescript("""
                    CREATE TABLE downloads(id TEXT PRIMARY KEY, video_id TEXT NOT NULL, media_json TEXT NOT NULL, kind TEXT NOT NULL,
                        state TEXT NOT NULL, downloaded INTEGER NOT NULL DEFAULT 0, total INTEGER, speed REAL, eta REAL,
                        filepath TEXT, size INTEGER, error TEXT, created_at REAL NOT NULL, finished_at REAL);
                    PRAGMA user_version=5;
                """)
        if version < 6:
            with self.db:
                self.db.executescript("""
                    CREATE TABLE hidden_channels(channel_id TEXT PRIMARY KEY, title TEXT NOT NULL, hidden_at REAL NOT NULL);
                    PRAGMA user_version=6;
                """)
        if version < 7:
            with self.db:
                self.db.executescript("""
                    CREATE TABLE queue_sessions(id TEXT PRIMARY KEY, name TEXT NOT NULL, items_json TEXT NOT NULL,
                        item_count INTEGER NOT NULL, duration REAL, created_at REAL NOT NULL, updated_at REAL NOT NULL);
                    CREATE TABLE listening(day TEXT NOT NULL, video_id TEXT NOT NULL, seconds REAL NOT NULL, PRIMARY KEY(day,video_id));
                    CREATE TABLE sponsor_savings(day TEXT PRIMARY KEY, seconds REAL NOT NULL, segments INTEGER NOT NULL);
                    PRAGMA user_version=7;
                """)
        if version < 8:
            with self.db:
                self.db.executescript("""
                    CREATE TABLE playlist_resume(playlist_id TEXT PRIMARY KEY, entry_index INTEGER NOT NULL,
                        video_id TEXT, position REAL NOT NULL, updated_at REAL NOT NULL);
                    PRAGMA user_version=8;
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

    def saved_media_ids(self) -> list[str]:
        return [row[0] for row in self.db.execute("SELECT video_id FROM saved_media ORDER BY saved_at DESC")]

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
            rows = self.db.execute("""SELECT h.play_id,h.started_at,m.metadata_json,p.position,p.duration FROM history h JOIN media m USING(video_id)
                LEFT JOIN watch_progress p USING(video_id) ORDER BY h.started_at DESC LIMIT ? OFFSET ?""", (limit + 1, offset)).fetchall()
            items = []
            for row in rows[:limit]:
                item = {**json.loads(row["metadata_json"]), "playId": row["play_id"], "startedAt": row["started_at"]}
                if row["position"] is not None: item["watchProgress"] = {"position": row["position"], "duration": row["duration"]}
                items.append(item)
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
        result = {"items": items, "offset": offset, "nextOffset": offset + limit if len(rows) > limit else None}
        if section == "history": result["total"] = self.db.execute("SELECT COUNT(*) FROM history").fetchone()[0]
        return result

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
            self.db.execute("DELETE FROM playlist_resume WHERE playlist_id=?", (playlist_id,))

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

    _DOWNLOAD_FIELDS = ("state", "downloaded", "total", "speed", "eta", "filepath", "size", "error", "finished_at")

    def create_download(self, download_id: str, media: dict[str, Any], kind: str) -> None:
        with self.db:
            self.db.execute("INSERT INTO downloads(id,video_id,media_json,kind,state,created_at) VALUES(?,?,?,?,?,?)",
                            (download_id, media["videoId"], self._json(media), kind, "queued", time.time()))

    def update_download(self, download_id: str, **fields: Any) -> None:
        names = [name for name in fields if name in self._DOWNLOAD_FIELDS]
        if not names: return
        with self.db:
            self.db.execute(f"UPDATE downloads SET {','.join(f'{name}=?' for name in names)} WHERE id=?", (*[fields[name] for name in names], download_id))

    def downloads(self) -> list[dict[str, Any]]:
        rows = self.db.execute("SELECT * FROM downloads ORDER BY created_at DESC LIMIT 500").fetchall()
        return [{"id": row["id"], "videoId": row["video_id"], "media": json.loads(row["media_json"]), "kind": row["kind"],
                 "state": row["state"], "downloaded": row["downloaded"], "total": row["total"], "speed": row["speed"],
                 "eta": row["eta"], "filepath": row["filepath"], "size": row["size"], "error": row["error"],
                 "createdAt": row["created_at"], "finishedAt": row["finished_at"]} for row in rows]

    def download(self, download_id: str) -> dict[str, Any] | None:
        return next((row for row in self.downloads() if row["id"] == download_id), None)

    def delete_download(self, download_id: str) -> None:
        with self.db: self.db.execute("DELETE FROM downloads WHERE id=?", (download_id,))

    def interrupt_downloads(self) -> None:
        with self.db:
            self.db.execute("UPDATE downloads SET state='failed', error='Прервано перезапуском сервиса', speed=NULL, eta=NULL WHERE state IN ('queued','running','paused')")

    def hide_channel(self, channel_id: str, title: str) -> None:
        if not channel_id: raise OmaTubeError("invalid_request", "Не указан канал")
        with self.db:
            self.db.execute("INSERT INTO hidden_channels(channel_id,title,hidden_at) VALUES(?,?,?) ON CONFLICT(channel_id) DO NOTHING", (channel_id, title or channel_id, time.time()))

    def unhide_channel(self, channel_id: str | None) -> None:
        with self.db:
            if channel_id: self.db.execute("DELETE FROM hidden_channels WHERE channel_id=?", (channel_id,))
            else: self.db.execute("DELETE FROM hidden_channels")

    def hidden_channels(self) -> list[dict[str, Any]]:
        return [{"id": row[0], "title": row[1]} for row in self.db.execute("SELECT channel_id,title FROM hidden_channels ORDER BY hidden_at DESC").fetchall()]

    def playlist_id_by_name(self, name: str) -> str | None:
        row = self.db.execute("SELECT id FROM playlists WHERE name=? AND origin_json IS NULL ORDER BY created_at LIMIT 1", (name,)).fetchone()
        return row[0] if row else None

    def subscribe(self, channel: dict[str, Any]) -> None:
        channel_id = channel.get("id")
        if not isinstance(channel_id, str) or not channel_id: raise OmaTubeError("invalid_request", "Некорректный канал")
        with self.db:
            self.db.execute("INSERT INTO subscriptions(channel_id,title,thumbnail_url,metadata_json,subscribed_at) VALUES(?,?,?,?,?) "
                            "ON CONFLICT(channel_id) DO UPDATE SET title=excluded.title,thumbnail_url=excluded.thumbnail_url,metadata_json=excluded.metadata_json",
                            (channel_id, str(channel.get("title") or channel_id), channel.get("thumbnailUrl"), self._json(channel), time.time()))

    def unsubscribe(self, channel_id: str) -> None:
        with self.db:
            self.db.execute("DELETE FROM feed_items WHERE channel_id=?", (channel_id,))
            self.db.execute("DELETE FROM subscriptions WHERE channel_id=?", (channel_id,))

    def is_subscribed(self, channel_id: str) -> bool:
        return self.db.execute("SELECT 1 FROM subscriptions WHERE channel_id=?", (channel_id,)).fetchone() is not None

    def subscriptions(self) -> list[dict[str, Any]]:
        rows = self.db.execute("""SELECT s.metadata_json, s.channel_id, s.title, s.thumbnail_url,
            (SELECT COUNT(*) FROM feed_items f WHERE f.channel_id=s.channel_id AND f.seen=0) AS new_count
            FROM subscriptions s ORDER BY s.title COLLATE NOCASE""").fetchall()
        return [{**json.loads(row["metadata_json"]), "id": row["channel_id"], "title": row["title"],
                 "thumbnailUrl": row["thumbnail_url"], "newCount": row["new_count"]} for row in rows]

    def subscription_ids(self) -> list[str]:
        return [row[0] for row in self.db.execute("SELECT channel_id FROM subscriptions").fetchall()]

    def add_feed_items(self, channel_id: str, items: list[dict[str, Any]], initial: bool = False) -> int:
        added = 0
        for item in items:
            published = item.get("publishedAt")
            try: stamp = datetime.fromisoformat(str(published).replace("Z", "+00:00")).timestamp()
            except ValueError: stamp = time.time()
            self.upsert_media({key: value for key, value in item.items() if key != "publishedAt"} | {"publishedAt": published})
            with self.db:
                cursor = self.db.execute("INSERT OR IGNORE INTO feed_items(video_id,channel_id,published_at,seen) VALUES(?,?,?,?)",
                                         (item["videoId"], channel_id, stamp, 1 if initial else 0))
            added += cursor.rowcount
        with self.db:
            self.db.execute("UPDATE subscriptions SET checked_at=? WHERE channel_id=?", (time.time(), channel_id))
        return added

    def feed(self, offset: int = 0, limit: int = 60) -> dict[str, Any]:
        offset = max(0, int(offset)); limit = min(100, max(1, int(limit)))
        rows = self.db.execute("""SELECT m.metadata_json, f.published_at, f.seen, p.position, p.duration
            FROM feed_items f JOIN media m USING(video_id) LEFT JOIN watch_progress p USING(video_id)
            ORDER BY f.published_at DESC LIMIT ? OFFSET ?""", (limit + 1, offset)).fetchall()
        items = []
        for row in rows[:limit]:
            item = json.loads(row["metadata_json"]); item["publishedTs"] = row["published_at"]; item["isNew"] = not row["seen"]
            if row["position"] is not None: item["watchProgress"] = {"position": row["position"], "duration": row["duration"]}
            items.append(item)
        return {"items": items, "offset": offset, "nextOffset": offset + limit if len(rows) > limit else None,
                "newCount": self.new_count()}

    def new_count(self) -> int:
        return self.db.execute("SELECT COUNT(*) FROM feed_items WHERE seen=0").fetchone()[0]

    def mark_feed_seen(self) -> None:
        with self.db: self.db.execute("UPDATE feed_items SET seen=1 WHERE seen=0")

    def last_checked(self) -> float | None:
        return self.db.execute("SELECT MAX(checked_at) FROM subscriptions").fetchone()[0]

    def save_progress(self, video_id: str, position: float, duration: float) -> None:
        if duration <= 0: return
        with self.db:
            self.db.execute("INSERT INTO watch_progress(video_id,position,duration,updated_at) VALUES(?,?,?,?) ON CONFLICT(video_id) DO UPDATE SET position=excluded.position,duration=excluded.duration,updated_at=excluded.updated_at",
                            (video_id, min(position, duration), duration, time.time()))

    def progress_for(self, video_ids: list[str]) -> dict[str, dict[str, float]]:
        if not video_ids: return {}
        marks = ",".join("?" * len(video_ids[:200]))
        rows = self.db.execute(f"SELECT video_id,position,duration FROM watch_progress WHERE video_id IN ({marks})", video_ids[:200]).fetchall()
        return {row[0]: {"position": row[1], "duration": row[2]} for row in rows}

    def playlist_membership(self, video_id: str) -> list[str]:
        rows = self.db.execute("SELECT DISTINCT playlist_id FROM playlist_items WHERE video_id=?", (video_id,)).fetchall()
        return [row[0] for row in rows]

    def remove_playlist_video(self, playlist_id: str, video_id: str) -> int:
        self._require_playlist(playlist_id)
        with self.db:
            removed = self.db.execute("DELETE FROM playlist_items WHERE playlist_id=? AND video_id=?", (playlist_id, video_id)).rowcount
            rows = self.db.execute("SELECT entry_id FROM playlist_items WHERE playlist_id=? ORDER BY position", (playlist_id,)).fetchall()
            self.db.execute("UPDATE playlist_items SET position=-position-1 WHERE playlist_id=?", (playlist_id,))
            for index, row in enumerate(rows):
                self.db.execute("UPDATE playlist_items SET position=? WHERE entry_id=?", (index, row[0]))
            self.db.execute("UPDATE playlists SET updated_at=? WHERE id=?", (time.time(), playlist_id))
        return removed

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
        result["resume"] = self.playlist_resume(playlist_id)
        return result

    def save_playlist_resume(self, playlist_id: str, index: int, video_id: str | None, position: float) -> None:
        with self.db:
            self.db.execute(
                "INSERT INTO playlist_resume(playlist_id,entry_index,video_id,position,updated_at) VALUES(?,?,?,?,?) "
                "ON CONFLICT(playlist_id) DO UPDATE SET entry_index=excluded.entry_index,video_id=excluded.video_id,"
                "position=excluded.position,updated_at=excluded.updated_at",
                (playlist_id, max(0, int(index)), video_id, max(0.0, float(position)), time.time()),
            )

    def playlist_resume(self, playlist_id: str) -> dict[str, Any] | None:
        row = self.db.execute("SELECT entry_index,video_id,position,updated_at FROM playlist_resume WHERE playlist_id=?",
                              (playlist_id,)).fetchone()
        if not row: return None
        return {"index": row["entry_index"], "videoId": row["video_id"], "position": row["position"], "updatedAt": row["updated_at"]}

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

    def remove_history_entry(self, play_id: str) -> None:
        with self.db: self.db.execute("DELETE FROM history WHERE play_id=?", (play_id,))

    def continue_watching(self, limit: int = 4) -> list[dict[str, Any]]:
        rows = self.db.execute("""SELECT m.metadata_json,p.position,p.duration FROM watch_progress p JOIN media m USING(video_id)
            WHERE p.duration>0 AND p.position>=15 AND p.position<p.duration*0.95 ORDER BY p.updated_at DESC LIMIT ?""", (limit,)).fetchall()
        return [{**json.loads(row["metadata_json"]), "watchProgress": {"position": row["position"], "duration": row["duration"]}} for row in rows]

    def recent_video_ids(self, limit: int = 5) -> list[str]:
        rows = self.db.execute("SELECT video_id FROM history GROUP BY video_id ORDER BY MAX(started_at) DESC LIMIT ?", (limit,)).fetchall()
        return [row[0] for row in rows]

    def watched_ids(self) -> set[str]:
        return {row[0] for row in self.db.execute("SELECT DISTINCT video_id FROM history")}

    @staticmethod
    def _day(timestamp: float | None = None) -> str:
        return time.strftime("%Y-%m-%d", time.localtime(timestamp if timestamp is not None else time.time()))

    def add_listening(self, video_id: str, seconds: float, timestamp: float | None = None) -> None:
        if not video_id or seconds <= 0: return
        with self.db:
            self.db.execute("INSERT INTO listening(day,video_id,seconds) VALUES(?,?,?) ON CONFLICT(day,video_id) DO UPDATE SET seconds=seconds+excluded.seconds",
                            (self._day(timestamp), video_id, seconds))

    def add_sponsor_saving(self, seconds: float, timestamp: float | None = None) -> None:
        if seconds <= 0: return
        with self.db:
            self.db.execute("INSERT INTO sponsor_savings(day,seconds,segments) VALUES(?,?,1) ON CONFLICT(day) DO UPDATE SET seconds=seconds+excluded.seconds,segments=segments+1",
                            (self._day(timestamp), seconds))

    def stats(self, period: str, today: date | None = None) -> dict[str, Any]:
        if period not in {"week", "month", "all"}: raise OmaTubeError("invalid_request", "Неизвестный период статистики")
        today = today or date.today()
        span = {"week": 7, "month": 30}.get(period)
        start = today - timedelta(days=span - 1) if span else date(1970, 1, 1)
        low, high = start.isoformat(), today.isoformat()
        total = self.db.execute("SELECT COALESCE(SUM(seconds),0) FROM listening WHERE day BETWEEN ? AND ?", (low, high)).fetchone()[0]
        previous = None
        if span:
            pstart = start - timedelta(days=span)
            previous = self.db.execute("SELECT COALESCE(SUM(seconds),0) FROM listening WHERE day BETWEEN ? AND ?",
                                       (pstart.isoformat(), (start - timedelta(days=1)).isoformat())).fetchone()[0]
        began = time.mktime(start.timetuple()) if span else 0
        plays = self.db.execute("SELECT COUNT(*) FROM history WHERE started_at>=?", (began,)).fetchone()[0]
        authors = "json_extract(m.metadata_json,'$.author')"
        channels = self.db.execute(f"SELECT COUNT(DISTINCT {authors}) FROM listening l JOIN media m ON m.video_id=l.video_id WHERE l.day BETWEEN ? AND ?", (low, high)).fetchone()[0]
        saved = self.db.execute("SELECT COALESCE(SUM(seconds),0),COALESCE(SUM(segments),0) FROM sponsor_savings WHERE day BETWEEN ? AND ?", (low, high)).fetchone()
        daily = {row[0]: row[1] for row in self.db.execute("SELECT day,SUM(seconds) FROM listening WHERE day BETWEEN ? AND ? GROUP BY day", (low, high))}
        bars: list[dict[str, Any]] = []
        if period == "week":
            names = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
            for offset in range(7):
                day = start + timedelta(days=offset)
                bars.append({"label": names[day.weekday()], "seconds": daily.get(day.isoformat(), 0.0)})
        elif period == "month":
            for index in range(6):
                first = start + timedelta(days=index * 5)
                bars.append({"label": first.strftime("%d.%m"),
                             "seconds": sum(daily.get((first + timedelta(days=n)).isoformat(), 0.0) for n in range(5))})
        else:
            months: dict[str, float] = {}
            for day, seconds in daily.items(): months[day[:7]] = months.get(day[:7], 0.0) + seconds
            for key in sorted(months)[-8:]: bars.append({"label": key[5:] + "." + key[2:4], "seconds": months[key]})
        days_count = span or max(1, (today - date.fromisoformat(min(daily))).days + 1 if daily else 1)
        top_channels = [{"title": row[0] or "—", "seconds": row[1]} for row in self.db.execute(
            f"SELECT {authors} AS a,SUM(l.seconds) AS s FROM listening l JOIN media m ON m.video_id=l.video_id WHERE l.day BETWEEN ? AND ? GROUP BY a ORDER BY s DESC LIMIT 5", (low, high))]
        top_tracks = [{"videoId": row[0], "title": row[1] or row[0], "author": row[2] or "", "plays": row[3]} for row in self.db.execute(
            "SELECT h.video_id,json_extract(m.metadata_json,'$.title'),json_extract(m.metadata_json,'$.author'),COUNT(*) AS c FROM history h JOIN media m USING(video_id) "
            "WHERE h.started_at>=? GROUP BY h.video_id ORDER BY c DESC, MAX(h.started_at) DESC LIMIT 5", (began,))]
        return {"period": period, "totalSeconds": total, "previousSeconds": previous, "plays": plays, "channels": channels,
                "sponsorSeconds": saved[0], "sponsorSegments": saved[1], "avgPerDay": total / days_count,
                "bars": bars, "topChannels": top_channels, "topTracks": top_tracks}

    def save_session(self, name: Any, media: list[dict[str, Any]]) -> dict[str, Any]:
        if not media: raise OmaTubeError("invalid_request", "Очередь пуста")
        text = str(name or "").strip()[:80] or time.strftime("Сессия %d.%m %H:%M")
        now = time.time(); session_id = str(uuid4())
        duration = sum(float(item["duration"]) for item in media if isinstance(item.get("duration"), (int, float)))
        with self.db:
            self.db.execute("INSERT INTO queue_sessions(id,name,items_json,item_count,duration,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",
                            (session_id, text, self._json(media), len(media), duration or None, now, now))
            for row in self.db.execute("SELECT id FROM queue_sessions ORDER BY updated_at DESC LIMIT -1 OFFSET 50").fetchall():
                self.db.execute("DELETE FROM queue_sessions WHERE id=?", (row[0],))
        return {"id": session_id, "name": text, "count": len(media), "duration": duration or None, "updatedAt": now}

    def sessions(self) -> list[dict[str, Any]]:
        rows = self.db.execute("SELECT id,name,item_count,duration,updated_at FROM queue_sessions ORDER BY updated_at DESC").fetchall()
        return [{"id": r[0], "name": r[1], "count": r[2], "duration": r[3], "updatedAt": r[4]} for r in rows]

    def session_media(self, session_id: str) -> list[dict[str, Any]]:
        row = self.db.execute("SELECT items_json FROM queue_sessions WHERE id=?", (session_id,)).fetchone()
        if not row: raise OmaTubeError("not_found", "Сессия не найдена")
        return json.loads(row[0])

    def delete_session(self, session_id: str) -> None:
        with self.db: self.db.execute("DELETE FROM queue_sessions WHERE id=?", (session_id,))
