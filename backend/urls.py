from __future__ import annotations

import re
from typing import Any
from urllib.parse import parse_qs, urlencode, urlparse

from .errors import OmaTubeError

VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{6,32}$")
PLAYLIST_ID = re.compile(r"^[A-Za-z0-9_-]{6,128}$")
TIMESTAMP = re.compile(r"^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$")
MAX_START = 24 * 3600
ALLOWED_HOSTS = {
    "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"
}


def canonical_video_url(video_id: str) -> str:
    if not VIDEO_ID.fullmatch(video_id):
        raise OmaTubeError("invalid_request", "Некорректный идентификатор видео")
    return f"https://www.youtube.com/watch?{urlencode({'v': video_id})}"


def parse_timestamp(raw: str | None) -> float | None:
    """YouTube `t`/`start` values: `90`, `90s`, `1m30s`, `1h2m3s`."""
    if not raw: return None
    match = TIMESTAMP.fullmatch(raw.strip().lower())
    if not match or not any(match.groups()): return None
    hours, minutes, seconds = (int(value or 0) for value in match.groups())
    total = hours * 3600 + minutes * 60 + seconds
    return float(total) if 0 < total <= MAX_START else None


def normalize_youtube_url(raw: str) -> dict[str, Any]:
    if not isinstance(raw, str) or not raw.strip():
        raise OmaTubeError("invalid_request", "Введите ссылку YouTube")
    try:
        parsed = urlparse(raw.strip())
    except ValueError as exc:
        raise OmaTubeError("invalid_request", "Некорректная ссылка YouTube") from exc
    host = (parsed.hostname or "").lower().rstrip(".")
    if parsed.scheme != "https" or host not in ALLOWED_HOSTS or parsed.username or parsed.password or parsed.port:
        raise OmaTubeError("invalid_request", "Разрешены только HTTPS-ссылки YouTube")
    query = parse_qs(parsed.query, keep_blank_values=False)
    video_id: str | None = None
    playlist_id: str | None = None
    if host == "youtu.be":
        video_id = parsed.path.strip("/").split("/")[0]
    elif parsed.path == "/watch":
        video_id = (query.get("v") or [None])[0]
    elif parsed.path.startswith("/shorts/"):
        video_id = parsed.path.split("/", 3)[2]
    elif parsed.path == "/playlist":
        playlist_id = (query.get("list") or [None])[0]
    if video_id and VIDEO_ID.fullmatch(video_id):
        result: dict[str, Any] = {"kind": "video", "videoId": video_id, "canonicalUrl": canonical_video_url(video_id)}
        start = parse_timestamp((query.get("t") or query.get("start") or [None])[0])
        if start is not None: result["start"] = start
        return result
    if playlist_id and PLAYLIST_ID.fullmatch(playlist_id):
        return {"kind": "playlist", "id": playlist_id,
                "canonicalUrl": f"https://www.youtube.com/playlist?{urlencode({'list': playlist_id})}"}
    raise OmaTubeError("invalid_request", "Поддерживаются ссылки на видео, Shorts и плейлисты YouTube")
