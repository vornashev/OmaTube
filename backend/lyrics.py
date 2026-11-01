from __future__ import annotations

import asyncio
import json
import re
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

API = "https://lrclib.net/api"
MAX_RESPONSE = 256 * 1024
LRC_LINE = re.compile(r"^\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]\s*(.*)$")
NOISE = re.compile(r"\s*[\(\[][^)\]]*(official|video|audio|lyrics?|clip|hd|hq|4k|visuali[sz]er|remaster)[^)\]]*[\)\]]", re.I)


def clean_title(title: str, author: str) -> tuple[str, str]:
    artist = re.sub(r"\s*-\s*Topic$", "", author or "", flags=re.I).strip()
    track = NOISE.sub("", title or "").strip()
    for separator in (" - ", " — ", " – "):
        if separator in track:
            head, tail = track.split(separator, 1)
            if head.strip() and tail.strip():
                artist, track = head.strip(), tail.strip()
                break
    return artist, track


def parse_lrc(text: str) -> list[dict[str, Any]]:
    lines: list[dict[str, Any]] = []
    for raw in text.splitlines():
        match = LRC_LINE.match(raw.strip())
        if not match: continue
        fraction = match.group(3) or "0"
        seconds = int(match.group(1)) * 60 + int(match.group(2)) + int(fraction) / (10 ** len(fraction))
        lines.append({"t": round(seconds, 2), "text": match.group(4)})
    return lines


def _request(url: str, timeout: float) -> Any:
    request = urllib.request.Request(url, headers={"User-Agent": "OmaTube (https://github.com/vornashev/OmaTube)"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read(MAX_RESPONSE))
    except urllib.error.HTTPError as error:
        if error.code == 404: return None
        raise


def pick(payload: Any, duration: float | None) -> dict[str, Any] | None:
    candidates = payload if isinstance(payload, list) else ([payload] if isinstance(payload, dict) else [])
    candidates = [row for row in candidates if isinstance(row, dict) and (row.get("syncedLyrics") or row.get("plainLyrics"))]
    if duration:
        close = [row for row in candidates if isinstance(row.get("duration"), (int, float)) and abs(row["duration"] - duration) <= 5]
        candidates = close or candidates
    candidates.sort(key=lambda row: not row.get("syncedLyrics"))
    return candidates[0] if candidates else None


def client_fetcher(client):
    return lambda url, timeout: client.json(url, timeout, not_found=None)


class LyricsService:
    def __init__(self, timeout: float = 4.0, fetcher=None) -> None:
        self.timeout = timeout
        self._fetcher = fetcher or _request
        self._cache: dict[tuple[str, str, int], dict[str, Any]] = {}

    async def lookup(self, title: str, author: str, duration: float | None) -> dict[str, Any]:
        artist, track = clean_title(title, author)
        key = (artist.lower(), track.lower(), int(duration or 0))
        if key in self._cache: return self._cache[key]
        base = {"artist_name": artist, "track_name": track}
        if duration: base["duration"] = str(int(duration))
        found = None
        try:
            found = pick(await asyncio.to_thread(self._fetcher, f"{API}/get?{urllib.parse.urlencode(base)}", self.timeout), duration)
            if not found:
                query = urllib.parse.urlencode({"q": f"{artist} {track}".strip()})
                found = pick(await asyncio.to_thread(self._fetcher, f"{API}/search?{query}", self.timeout), duration)
        except (OSError, ValueError, urllib.error.URLError):
            return {"found": False, "error": "network"}
        if not found:
            result: dict[str, Any] = {"found": False}
        else:
            synced = parse_lrc(found.get("syncedLyrics") or "")
            plain = [{"t": None, "text": line} for line in (found.get("plainLyrics") or "").splitlines()] if not synced else []
            result = {"found": True, "synced": bool(synced), "lines": synced or plain, "source": "LRCLIB",
                      "artist": found.get("artistName"), "track": found.get("trackName")}
        if len(self._cache) >= 64: self._cache.pop(next(iter(self._cache)))
        self._cache[key] = result
        return result
