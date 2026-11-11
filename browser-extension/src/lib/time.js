// Pure helpers shared by the content script, the service worker and node tests.
(function (root) {
  "use strict";

  const MAX_START = 24 * 3600;
  const VIDEO_ID = /^[A-Za-z0-9_-]{6,32}$/;
  const TIMESTAMP = /^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$/;
  // Starting closer than this to the end would just trigger the next track.
  const END_GUARD = 5;

  // YouTube `t` / `start` values: "90", "90s", "1m30s", "1h2m3s".
  function parseTimestamp(raw) {
    if (!raw) return null;
    const match = TIMESTAMP.exec(String(raw).trim().toLowerCase());
    if (!match || !match.slice(1).some(Boolean)) return null;
    const [hours, minutes, seconds] = match.slice(1).map(value => Number(value || 0));
    const total = hours * 3600 + minutes * 60 + seconds;
    return total > 0 && total <= MAX_START ? total : null;
  }

  // Video id and timestamp from any supported YouTube URL; null for everything else.
  function parseVideoUrl(raw) {
    let url;
    try { url = new URL(raw); } catch (_) { return null; }
    const host = url.hostname.replace(/^www\.|^m\./, "");
    let videoId = null;
    if (host === "youtu.be") videoId = url.pathname.split("/")[1];
    else if (host === "youtube.com" || host === "music.youtube.com") {
      if (url.pathname === "/watch") videoId = url.searchParams.get("v");
      else if (/^\/(shorts|live|embed)\//.test(url.pathname)) videoId = url.pathname.split("/")[2];
    }
    if (!videoId || !VIDEO_ID.test(videoId)) return null;
    return { videoId, start: parseTimestamp(url.searchParams.get("t") || url.searchParams.get("start")) };
  }

  // Position to resume from. `null` means "live edge", which the host sends without a start.
  function resumePosition({ current = 0, duration = null, ended = false, live = false, adShowing = false,
                            lastContent = null, urlStart = null, rewind = 0 } = {}) {
    if (live) return null;
    if (ended) return 0;
    let base = adShowing ? (lastContent ?? urlStart ?? 0) : current;
    if (!Number.isFinite(base) || base < 0) base = 0;
    // During an ad `duration` belongs to the ad, so the end guard only applies to the video itself.
    if (!adShowing && Number.isFinite(duration) && duration > 0 && duration - base < END_GUARD) return 0;
    return Math.max(0, Math.floor(base - (Number(rewind) || 0)));
  }

  function formatClock(seconds) {
    const total = Math.max(0, Math.floor(Number(seconds) || 0));
    const hours = Math.floor(total / 3600), minutes = Math.floor(total % 3600 / 60), secs = total % 60;
    const pad = value => String(value).padStart(2, "0");
    return hours ? `${hours}:${pad(minutes)}:${pad(secs)}` : `${minutes}:${pad(secs)}`;
  }

  root.OmaTubeTime = { parseTimestamp, parseVideoUrl, resumePosition, formatClock, VIDEO_ID };
})(globalThis);
