from __future__ import annotations

import asyncio
import hashlib
import json
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

API = "https://sponsor.ajay.app/api/skipSegments"
CATEGORIES = ("sponsor", "intro", "outro", "selfpromo", "interaction", "preview", "music_offtopic")
ACTIONS = frozenset({"skip", "ask", "off"})
DEFAULT_ACTIONS = {
    "sponsor": "skip", "intro": "skip", "outro": "ask", "selfpromo": "skip",
    "interaction": "off", "preview": "off", "music_offtopic": "off",
}
MAX_RESPONSE = 512 * 1024


def hash_prefix(video_id: str) -> str:
    return hashlib.sha256(video_id.encode()).hexdigest()[:4]


def parse_segments(payload: Any, video_id: str) -> list[dict[str, Any]]:
    segments: list[dict[str, Any]] = []
    if not isinstance(payload, list): return segments
    for entry in payload:
        if not isinstance(entry, dict) or entry.get("videoID") != video_id: continue
        for row in entry.get("segments") or []:
            if not isinstance(row, dict) or row.get("actionType", "skip") != "skip": continue
            span = row.get("segment")
            category = row.get("category")
            if (category not in CATEGORIES or not isinstance(span, list) or len(span) != 2
                    or not all(isinstance(value, (int, float)) for value in span) or not 0 <= span[0] < span[1]):
                continue
            segments.append({"start": float(span[0]), "end": float(span[1]), "category": category,
                             "id": str(row.get("UUID") or f"{category}:{span[0]}")})
    return sorted(segments, key=lambda row: row["start"])


def _request(url: str, timeout: float) -> Any:
    request = urllib.request.Request(url, headers={"User-Agent": "OmaTube", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read(MAX_RESPONSE))
    except urllib.error.HTTPError as error:
        if error.code == 404: return []
        raise


def client_fetcher(client):
    return lambda url, timeout: client.json(url, timeout, not_found=[])


class SponsorBlock:
    def __init__(self, timeout: float = 6.0, fetcher=None) -> None:
        self.timeout = timeout
        self._fetcher = fetcher or _request
        self._cache: dict[tuple[str, tuple[str, ...]], list[dict[str, Any]]] = {}

    async def segments(self, video_id: str, categories: list[str]) -> list[dict[str, Any]]:
        wanted = tuple(sorted(category for category in categories if category in CATEGORIES))
        if not wanted or not video_id: return []
        key = (video_id, wanted)
        if key in self._cache: return self._cache[key]
        query = urllib.parse.urlencode({"categories": json.dumps(list(wanted)), "actionTypes": json.dumps(["skip"])})
        url = f"{API}/{hash_prefix(video_id)}?{query}"
        try:
            payload = await asyncio.to_thread(self._fetcher, url, self.timeout)
        except (OSError, ValueError, urllib.error.URLError):
            return []
        result = parse_segments(payload, video_id)
        if len(self._cache) >= 64: self._cache.pop(next(iter(self._cache)))
        self._cache[key] = result
        return result
