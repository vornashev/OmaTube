from __future__ import annotations

import re
from urllib.parse import parse_qs, urlencode, urlparse

from .errors import OmaTubeError

VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{6,32}$")
PLAYLIST_ID = re.compile(r"^[A-Za-z0-9_-]{6,128}$")
ALLOWED_HOSTS = {
    "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"
}


def canonical_video_url(video_id: str) -> str:
    if not VIDEO_ID.fullmatch(video_id):
        raise OmaTubeError("invalid_request", "Некорректный идентификатор видео")
    return f"https://www.youtube.com/watch?{urlencode({'v': video_id})}"


def normalize_youtube_url(raw: str) -> dict[str, str]:
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
        return {"kind": "video", "videoId": video_id, "canonicalUrl": canonical_video_url(video_id)}
    if playlist_id and PLAYLIST_ID.fullmatch(playlist_id):
        return {"kind": "playlist", "id": playlist_id,
                "canonicalUrl": f"https://www.youtube.com/playlist?{urlencode({'list': playlist_id})}"}
    raise OmaTubeError("invalid_request", "Поддерживаются ссылки на видео, Shorts и плейлисты YouTube")
