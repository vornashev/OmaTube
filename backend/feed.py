from __future__ import annotations

import asyncio
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from typing import Any

FEED_URL = "https://www.youtube.com/feeds/videos.xml?channel_id="
NS = {"a": "http://www.w3.org/2005/Atom", "yt": "http://www.youtube.com/xml/schemas/2015", "m": "http://search.yahoo.com/mrss/"}
MAX_FEED = 512 * 1024


def parse_feed(data: bytes) -> dict[str, Any]:
    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        return {"title": None, "items": []}
    channel_title = root.findtext("a:author/a:name", default=None, namespaces=NS)
    items: list[dict[str, Any]] = []
    for entry in root.findall("a:entry", NS):
        video_id = entry.findtext("yt:videoId", default="", namespaces=NS)
        if not video_id: continue
        views = entry.find("m:group/m:community/m:statistics", NS)
        thumb = entry.find("m:group/m:thumbnail", NS)
        link = entry.find("a:link[@rel='alternate']", NS)
        try: view_count = int(views.get("views")) if views is not None and views.get("views") else None
        except ValueError: view_count = None
        items.append({
            "videoId": video_id, "source": "youtube",
            "title": entry.findtext("a:title", default=video_id, namespaces=NS),
            "author": entry.findtext("a:author/a:name", default=channel_title or "", namespaces=NS),
            "authorId": entry.findtext("yt:channelId", default=None, namespaces=NS),
            "thumbnailUrl": thumb.get("url") if thumb is not None else None,
            "canonicalUrl": link.get("href") if link is not None else f"https://www.youtube.com/watch?v={video_id}",
            "viewCount": view_count, "duration": None,
            "publishedAt": entry.findtext("a:published", default=None, namespaces=NS),
        })
    return {"title": channel_title, "items": items}


def _fetch(channel_id: str, timeout: float) -> bytes:
    request = urllib.request.Request(FEED_URL + channel_id, headers={"User-Agent": "OmaTube"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read(MAX_FEED)


def client_fetcher(client):
    def fetch(channel_id: str, timeout: float) -> bytes:
        reply = client.get_revalidated(FEED_URL + channel_id, timeout)
        if reply.status >= 400: raise OSError(f"HTTP {reply.status}")
        return reply.body[:MAX_FEED]
    return fetch


class FeedService:
    def __init__(self, fetcher=None, timeout: float = 8.0, concurrency: int = 6) -> None:
        self._fetcher = fetcher or _fetch
        self.timeout = timeout
        self._limit = asyncio.Semaphore(concurrency)

    async def fetch(self, channel_id: str) -> dict[str, Any] | None:
        async with self._limit:
            try:
                data = await asyncio.to_thread(self._fetcher, channel_id, self.timeout)
            except (OSError, ValueError, urllib.error.URLError):
                return None
        return parse_feed(data)
