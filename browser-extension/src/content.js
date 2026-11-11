// "Watch in OmaTube" buttons on YouTube / YouTube Music pages.
// YouTube enforces Trusted Types, so all markup is built with DOM APIs (no innerHTML).
(() => {
  "use strict";
  if (window.__omatubeContent) return;
  window.__omatubeContent = true;

  const { parseTimestamp, parseVideoUrl, resumePosition, formatClock, VIDEO_ID } = globalThis.OmaTubeTime;
  const DEFAULTS = {
    defaultAction: "now", afterTransfer: "close", rewind: 3, placement: "actions",
    shorts: true, music: true, contextMenu: true, thumbnails: true,
  };
  const SVG = "http://www.w3.org/2000/svg";
  const ICON_PATHS = {
    logo: ["M4 7a3 3 0 0 1 3-3h10a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3z", "M10 9l5 3-5 3z"],
    chevron: ["M6 9l6 6 6-6"],
    now: ["M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"],
    next: ["M21 4v16", "M5 4l10 8-10 8z"],
    end: ["M16 5H3", "M16 12H3", "M9 19H3", "M16 16l-3 3 3 3", "M21 5v12a2 2 0 0 1-2 2h-6"],
    add: ["M11 12H3", "M16 6H3", "M16 18H3", "M18 9v6", "M21 12h-6"],
    check: ["M5 12l5 5L20 7"],
    ordered: ["M10 12h11", "M10 18h11", "M10 6h11", "M4 10h2", "M4 6h1v4", "M6 18H4c0-1 2-2 2-3s-1-1.5-2-1"],
    remove: ["M18 6L6 18", "M6 6l12 12"],
  };
  const t = (key, ...subs) => chrome.i18n.getMessage(key, subs.map(String)) || key;

  let settings = { ...DEFAULTS };
  let busy = false;
  let lastContent = { videoId: null, time: null };
  let menu = null;
  let toastTimer = null;

  // ---------- page model ----------

  function pageKind() {
    if (location.hostname === "music.youtube.com") return settings.music && location.pathname === "/watch" ? "music" : null;
    if (location.pathname === "/watch") return "watch";
    if (location.pathname.startsWith("/shorts/")) return settings.shorts ? "shorts" : null;
    return null;
  }

  function currentVideoId() {
    const id = location.pathname.startsWith("/shorts/")
      ? location.pathname.split("/")[2]
      : new URLSearchParams(location.search).get("v");
    return id && VIDEO_ID.test(id) ? id : null;
  }

  function videoElement() {
    const selectors = location.pathname.startsWith("/shorts/")
      ? ["ytd-reel-video-renderer[is-active] video", "#shorts-player video"]
      : location.hostname === "music.youtube.com"
        ? ["ytmusic-player video", "video"]
        : ["#movie_player video.html5-main-video", "video.html5-main-video"];
    for (const selector of selectors) {
      const video = document.querySelector(selector);
      if (video) return video;
    }
    return null;
  }

  const textOf = selector => document.querySelector(selector)?.textContent?.trim() || null;

  function metadata() {
    const music = location.hostname === "music.youtube.com";
    const shorts = location.pathname.startsWith("/shorts/");
    const title = music ? textOf("ytmusic-player-bar .title")
      : shorts ? textOf("ytd-reel-video-renderer[is-active] h2") || textOf("yt-shorts-video-title-view-model")
      : textOf("ytd-watch-metadata h1");
    const authorLink = document.querySelector(music ? "ytmusic-player-bar .byline a"
      : shorts ? "ytd-reel-video-renderer[is-active] ytd-channel-name a, ytd-reel-video-renderer[is-active] .ytReelChannelBarViewModelChannelName a"
      : "ytd-watch-metadata #owner ytd-channel-name a");
    const channelId = authorLink?.getAttribute("href")?.match(/\/channel\/(UC[\w-]{22})/)?.[1] || null;
    return {
      title: title || document.title.replace(/^\(\d+\)\s*/, "").replace(/\s+-\s+YouTube( Music)?$/, "") || null,
      author: authorLink?.textContent?.trim() || null,
      channelId,
    };
  }

  function collect() {
    const videoId = currentVideoId();
    const video = videoElement();
    if (!videoId || !video) return null;
    const player = video.closest(".html5-video-player");
    const adShowing = Boolean(player?.classList.contains("ad-showing"));
    const live = video.duration === Infinity || Boolean(player?.querySelector(".ytp-time-display.ytp-live"));
    const duration = !adShowing && Number.isFinite(video.duration) ? video.duration : null;
    const start = resumePosition({
      current: video.currentTime, duration, ended: video.ended, live, adShowing,
      lastContent: lastContent.videoId === videoId ? lastContent.time : null,
      urlStart: parseTimestamp(new URLSearchParams(location.search).get("t")),
      rewind: settings.rewind,
    });
    return { video, payload: { videoId, start, live, duration, ...metadata() } };
  }

  // Remember the last position of the video itself, so a transfer during an ad resumes the video.
  document.addEventListener("timeupdate", event => {
    const video = event.target;
    if (!(video instanceof HTMLVideoElement) || video.closest(".html5-video-player")?.classList.contains("ad-showing")) return;
    if (video !== videoElement()) return;
    lastContent = { videoId: currentVideoId(), time: video.currentTime };
  }, true);

  // ---------- transfer ----------

  async function send(action = settings.defaultAction) {
    if (busy) return;
    const videoId = currentVideoId();
    const entry = videoId && queue.videos[videoId];
    if (entry && entry.position > 0 && action === "remove") { unqueue(videoId, entry.position); return; }
    if (entry && entry.position > 0 && (action === "next" || action === "end")) { moveQueued(videoId, action, entry); return; }
    const collected = collect();
    if (!collected) { toast(t("toastNoVideo"), { error: true }); return; }
    busy = true;
    closeMenu();
    const { video, payload } = collected;
    video.pause();
    toast(t("toastSending"), { sticky: true });
    const response = await request({ ...payload, action }, false);
    busy = false;
    report(response, action, payload.start, () => send(action), payload.videoId);
  }

  function report(response, action, start, retry, videoId = null) {
    if (response?.ok) {
      const message = action === "next" ? t("toastQueuedNext")
        : action === "end" ? t("toastQueuedEnd")
        : start ? t("toastSentAt", formatClock(start)) : t("toastSent");
      toast(message, { success: true });
      if (videoId && action !== "now") refreshQueue().then(() => {
        const entry = queue.videos[videoId];
        if (entry && entry.position > 0) toast(t("toastQueuedAt", entry.position, queue.total), { success: true });
      });
    } else {
      toast(response?.error?.message || t("errGeneric", "?"), { error: true, retry });
    }
    return Boolean(response?.ok);
  }

  async function request(payload, keepTab) {
    try {
      return await chrome.runtime.sendMessage({ type: "transfer", payload, keepTab });
    } catch (error) {
      // The extension was reloaded or updated while this tab stayed open.
      return { ok: false, error: { message: t("errGeneric", error?.message || "?") } };
    }
  }

  // ---------- UI ----------

  function icon(name, size = 20) {
    const svg = document.createElementNS(SVG, "svg");
    svg.setAttribute("viewBox", "0 0 24 24"); svg.setAttribute("width", size); svg.setAttribute("height", size);
    svg.setAttribute("fill", "none"); svg.setAttribute("stroke", "currentColor"); svg.setAttribute("stroke-width", "2");
    svg.setAttribute("stroke-linecap", "round"); svg.setAttribute("stroke-linejoin", "round"); svg.setAttribute("aria-hidden", "true");
    for (const d of ICON_PATHS[name]) {
      const path = document.createElementNS(SVG, "path"); path.setAttribute("d", d); svg.append(path);
    }
    return svg;
  }

  function element(tag, className, attributes = {}) {
    const node = document.createElement(tag);
    node.className = className;
    for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
    node.dataset.omatube = "";
    return node;
  }

  function stop(event) { event.preventDefault(); event.stopPropagation(); }

  function splitButton() {
    const wrap = element("div", "omatube-split");
    const main = element("button", "omatube-split-main", { type: "button", title: t("btnWatch") });
    const label = document.createElement("span"); label.textContent = t("btnWatch");
    main.append(icon(ICON_PATHS[settings.defaultAction] ? settings.defaultAction : "now", 18), label);
    main.addEventListener("click", event => { stop(event); send(); });
    const more = element("button", "omatube-split-more", { type: "button", title: t("btnMore"), "aria-label": t("btnMore"), "aria-haspopup": "menu" });
    more.append(icon("chevron", 18));
    more.addEventListener("click", event => { stop(event); toggleMenu(wrap); });
    wrap.append(main, more);
    wrap.addEventListener("contextmenu", event => { stop(event); toggleMenu(wrap); });
    return wrap;
  }

  // Compact icon button for the player bar, Shorts and YouTube Music; right click opens the menu.
  function iconButton(className) {
    const button = element("button", `omatube-icon ${className}`, { type: "button", title: t("btnWatch"), "aria-label": t("btnWatch") });
    button.append(icon("logo", className === "omatube-ytp" ? 24 : 22));
    button.addEventListener("click", event => { stop(event); send(); });
    button.addEventListener("contextmenu", event => { stop(event); toggleMenu(button); });
    return button;
  }

  function toggleMenu(anchor, pick = send, highlighted = settings.defaultAction) {
    if (menu) { closeMenu(); return; }
    menu = element("div", "omatube-menu", { role: "menu" });
    // A video that is already queued gets "move" and "remove" instead of "add".
    const entry = pick === send ? queue.videos[currentVideoId()] : null;
    const queued = entry && entry.position > 0;
    const rows = queued
      ? [["now", t("menuNow")], ["next", t("menuNextMove")], ["end", t("menuEndHere", entry.position)], ["remove", t("menuRemove")]]
      : [["now", t("menuNow")], ["next", t("menuNext")], ["end", t("menuEnd")]];
    for (const [action, text] of rows) {
      const item = element("button", "omatube-menu-item", { type: "button", role: "menuitem" });
      const label = document.createElement("span"); label.textContent = text;
      item.append(icon(action, 18), label);
      if (queued ? action === "end" : action === highlighted) item.classList.add("omatube-default");
      if (queued && action === "end") item.classList.add("omatube-here");
      if (action === "remove") item.classList.add("omatube-danger");
      item.addEventListener("click", event => { stop(event); closeMenu(); pick(action); });
      menu.append(item);
    }
    document.body.append(menu);
    const box = anchor.getBoundingClientRect();
    const width = menu.offsetWidth, height = menu.offsetHeight;
    const below = box.bottom + 6 + height <= innerHeight;
    menu.style.top = `${below ? box.bottom + 6 : Math.max(8, box.top - 6 - height)}px`;
    menu.style.left = `${Math.min(Math.max(8, box.right - width), innerWidth - width - 8)}px`;
    menu.querySelector("button")?.focus();
  }

  function closeMenu() { menu?.remove(); menu = null; }

  document.addEventListener("click", event => { if (menu && !menu.contains(event.target)) closeMenu(); }, true);
  document.addEventListener("keydown", event => { if (event.key === "Escape") closeMenu(); }, true);
  addEventListener("scroll", closeMenu, { passive: true });

  function toast(message, { error = false, success = false, sticky = false, retry = null } = {}) {
    document.querySelector(".omatube-toast")?.remove();
    clearTimeout(toastTimer);
    const node = element("div", "omatube-toast", { role: error ? "alert" : "status" });
    if (error) node.classList.add("omatube-error");
    if (success) node.classList.add("omatube-success");
    node.append(icon("logo", 18));
    const text = document.createElement("span"); text.textContent = message; node.append(text);
    if (retry) {
      const button = element("button", "omatube-toast-action", { type: "button" });
      button.textContent = t("toastRetry");
      button.addEventListener("click", event => { stop(event); retry(); });
      node.append(button);
    }
    document.body.append(node);
    if (!sticky) toastTimer = setTimeout(() => node.remove(), error ? 8000 : 2500);
  }

  // ---------- thumbnail button ----------
  // One floating button follows the hovered thumbnail. Injecting into every card would be
  // hidden by YouTube's inline preview, which plays in a separate element on top of the card.

  const THUMBNAIL = [
    "ytd-thumbnail", "yt-thumbnail-view-model", "ytm-shorts-lockup-view-model",
    "ytd-video-preview #media-container",
  ].join(", ");
  const CARD = [
    "yt-lockup-view-model", "ytd-rich-item-renderer", "ytd-video-renderer", "ytd-compact-video-renderer",
    "ytd-grid-video-renderer", "ytd-playlist-video-renderer", "ytd-playlist-panel-video-renderer",
    "ytm-shorts-lockup-view-model", "ytd-reel-item-renderer",
  ].join(", ");
  const MIN_THUMBNAIL_WIDTH = 120;

  let thumbButton = null;
  let thumbTarget = null;
  let thumbHideTimer = null;

  // The hovered thumbnail's video link; the inline preview carries its own link.
  function thumbnailLink(container) {
    const anchors = [container.closest("a[href]"), container.querySelector("a[href]"),
      container.closest(CARD)?.querySelector("a#thumbnail[href], a[href*='/watch'], a[href*='/shorts/']"),
      container.closest("ytd-video-preview")?.querySelector("a#media-container-link[href]")];
    for (const anchor of anchors) {
      const link = anchor && parseVideoUrl(anchor.href);
      if (link) return link;
    }
    return null;
  }

  function cardMetadata(container) {
    const card = container.closest(CARD);
    if (!card) return {};
    const title = card.querySelector("#video-title, .yt-lockup-metadata-view-model__title, h3")?.textContent?.trim();
    const authorLink = card.querySelector("ytd-channel-name a, a[href^='/@'], a[href^='/channel/']");
    return {
      title: title || null,
      author: authorLink?.textContent?.trim() || null,
      channelId: authorLink?.getAttribute("href")?.match(/\/channel\/(UC[\w-]{22})/)?.[1] || null,
    };
  }

  function thumbnailButton() {
    const button = element("button", "omatube-icon omatube-thumb", { type: "button", title: t("thumbQueue"), "aria-label": t("thumbQueue") });
    button.append(icon("logo", 20));
    button.addEventListener("click", event => { stop(event); queueThumbnail("end"); });
    button.addEventListener("contextmenu", event => { stop(event); toggleMenu(button, queueThumbnail, "end"); });
    button.addEventListener("mouseenter", () => clearTimeout(thumbHideTimer));
    button.addEventListener("mouseleave", hideThumbnailSoon);
    document.body.append(button);
    return button;
  }

  function showThumbnail(container, link) {
    const box = container.getBoundingClientRect();
    if (box.width < MIN_THUMBNAIL_WIDTH) { hideThumbnailSoon(); return; }
    clearTimeout(thumbHideTimer);
    // A queued video already carries its own mark in this corner.
    if (queue.videos[link.videoId]) { if (thumbButton) thumbButton.hidden = true; return; }
    thumbButton ??= thumbnailButton();
    if (thumbTarget?.link.videoId !== link.videoId) resetThumbnailIcon();
    thumbTarget = { container, link };
    thumbButton.style.top = `${box.top + 8}px`;
    thumbButton.style.left = `${box.left + 8}px`;
    thumbButton.hidden = false;
  }

  function hideThumbnailSoon() {
    clearTimeout(thumbHideTimer);
    thumbHideTimer = setTimeout(() => { if (thumbButton && !menu) thumbButton.hidden = true; }, 150);
  }

  function resetThumbnailIcon() {
    thumbButton?.classList.remove("omatube-done");
    thumbButton?.replaceChildren(icon("logo", 20));
  }

  async function queueThumbnail(action) {
    if (!thumbTarget) return;
    const { container, link } = thumbTarget;
    const button = thumbButton;
    button.disabled = true;
    const payload = { videoId: link.videoId, start: link.start, action, ...cardMetadata(container) };
    const response = await request(payload, true);
    button.disabled = false;
    if (report(response, action, link.start, () => queueThumbnail(action), link.videoId) && thumbTarget?.link.videoId === link.videoId) {
      button.classList.add("omatube-done");
      button.replaceChildren(icon("check", 18));
    }
  }

  document.addEventListener("mouseover", event => {
    if (!settings.thumbnails || location.hostname !== "www.youtube.com") return;
    const target = event.target;
    if (!(target instanceof Element) || thumbButton?.contains(target) || menu?.contains(target)) return;
    const container = target.closest(THUMBNAIL);
    const link = container && thumbnailLink(container);
    if (link) showThumbnail(container, link); else if (thumbButton && !thumbButton.hidden) hideThumbnailSoon();
  }, true);
  addEventListener("scroll", () => { if (thumbButton && !menu) thumbButton.hidden = true; }, { passive: true, capture: true });

  // ---------- queue marks ----------
  // The queue lives in OmaTube; the page only mirrors it, so marks survive reloads and navigation.

  const QUEUE_POLL_MS = 8000;
  const QUEUE_RETRY_MS = 60000;
  let queue = { videos: {}, total: 0 };
  let queueTimer = null;

  async function refreshQueue() {
    clearTimeout(queueTimer);
    let response = null;
    try { response = await chrome.runtime.sendMessage({ type: "queue" }); } catch (_) { /* extension reloaded */ }
    queue = response?.ok && response.result?.videos ? response.result : { videos: {}, total: 0 };
    queueTimer = setTimeout(() => { if (document.visibilityState === "visible") refreshQueue(); else queueTimer = null; },
      response?.ok ? QUEUE_POLL_MS : QUEUE_RETRY_MS);
    applyMarks();
  }

  function markTip(entry) {
    if (entry.position === 0) return t("markNow");
    const eta = entry.eta ? ` · ${t("markEta", `${Math.max(1, Math.round(entry.eta / 60))} ${t("unitMin")}`)}` : "";
    return `${t("markTip", entry.position, queue.total)}${eta} · ${t("markRemove")}`;
  }

  function buildMark(videoId) {
    const mark = element("button", "omatube-icon omatube-mark", { type: "button" });
    mark.dataset.videoId = videoId;
    mark.addEventListener("click", event => { stop(event); unqueue(mark.dataset.videoId, Number(mark.dataset.position)); });
    return mark;
  }

  function paintMark(mark, entry) {
    const key = `${entry.position}/${queue.total}/${entry.eta ?? ""}`;
    if (mark.dataset.key === key) return;
    mark.dataset.key = key; mark.dataset.position = entry.position;
    const named = entry.position <= 1;
    mark.classList.toggle("omatube-mark-wide", named);
    mark.classList.toggle("omatube-mark-now", entry.position === 0);
    mark.title = markTip(entry); mark.setAttribute("aria-label", mark.title);
    if (named) {
      const label = document.createElement("span"); label.textContent = t(entry.position === 0 ? "markNow" : "markNext");
      mark.replaceChildren(icon(entry.position === 0 ? "now" : "next", 16), label);
    } else {
      mark.textContent = String(entry.position);
    }
  }

  function applyMarks() {
    if (location.hostname === "www.youtube.com" && settings.thumbnails) {
      const seen = new Set();
      for (const container of document.querySelectorAll(THUMBNAIL)) {
        if (container.closest("ytd-video-preview") || container.getBoundingClientRect().width < MIN_THUMBNAIL_WIDTH) continue;
        const link = thumbnailLink(container);
        const entry = link && queue.videos[link.videoId];
        let mark = container.querySelector(":scope > .omatube-mark");
        if (!entry) { mark?.remove(); continue; }
        if (mark && mark.dataset.videoId !== link.videoId) { mark.remove(); mark = null; }
        if (!mark) { mark = buildMark(link.videoId); container.classList.add("omatube-marked"); container.append(mark); }
        paintMark(mark, entry);
        seen.add(mark);
      }
      document.querySelectorAll(".omatube-mark").forEach(mark => { if (!seen.has(mark)) mark.remove(); });
    } else {
      document.querySelectorAll(".omatube-mark").forEach(mark => mark.remove());
    }
    updateWatchLabel();
  }

  // The watch page button says where the open video sits in the queue.
  function updateWatchLabel() {
    const entry = queue.videos[currentVideoId()];
    const text = entry ? (entry.position === 0 ? t("markNow") : t("btnQueued", entry.position)) : t("btnWatch");
    document.querySelectorAll(".omatube-split-main").forEach(main => {
      const label = main.querySelector("span");
      if (label && label.textContent !== text) label.textContent = text;
      main.title = text;
      const state = entry ? "queued" : "idle";
      if (main.dataset.state === state) return;
      main.dataset.state = state;
      main.classList.toggle("omatube-queued", Boolean(entry));
      main.querySelector("svg")?.replaceWith(icon(entry ? "ordered" : ICON_PATHS[settings.defaultAction] ? settings.defaultAction : "now", 18));
    });
  }

  async function moveQueued(videoId, placement, entry) {
    const last = entry.position === queue.total;
    if (placement === "end" ? last : entry.position === 1) { toast(t("toastAlreadyThere")); return; }
    let response;
    try { response = await chrome.runtime.sendMessage({ type: "queue_move", videoId, placement }); }
    catch (error) { response = { ok: false, error: { message: t("errGeneric", error?.message || "?") } }; }
    if (!response?.ok) { toast(response?.error?.message || t("errGeneric", "?"), { error: true, retry: () => moveQueued(videoId, placement, entry) }); return; }
    await refreshQueue();
    const moved = queue.videos[videoId];
    toast(moved ? t("toastMovedTo", moved.position, queue.total) : t("toastQueuedEnd"), { success: true });
  }

  async function unqueue(videoId, position) {
    if (position === 0) return;
    let response;
    try { response = await chrome.runtime.sendMessage({ type: "unqueue", videoId }); }
    catch (error) { response = { ok: false, error: { message: t("errGeneric", error?.message || "?") } }; }
    if (response?.ok) toast(t("toastRemoved"), { success: true });
    else toast(response?.error?.message || t("errGeneric", "?"), { error: true, retry: () => unqueue(videoId, position) });
    refreshQueue();
  }

  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") refreshQueue(); });

  // ---------- injection ----------

  function place(target, create, key) {
    if (!target || target.querySelector(`:scope > [data-omatube-slot="${key}"]`)) return;
    const node = create();
    node.dataset.omatubeSlot = key;
    target.prepend(node);
  }

  function removeAll() {
    document.querySelectorAll("[data-omatube-slot]").forEach(node => node.remove());
    if (thumbButton) thumbButton.hidden = true;
    document.querySelectorAll(".omatube-mark").forEach(mark => mark.remove());
    closeMenu();
  }

  function ensure() {
    const kind = pageKind();
    // Drop buttons left over from another page type after SPA navigation.
    document.querySelectorAll("[data-omatube-slot]").forEach(node => {
      if (!node.dataset.omatubeSlot.startsWith(`${kind}:`)) node.remove();
    });
    if (kind === "watch") {
      if (settings.placement !== "player") place(document.querySelector("ytd-watch-metadata #actions"), splitButton, "watch:actions");
      if (settings.placement !== "actions") place(document.querySelector("#movie_player .ytp-right-controls"), () => iconButton("omatube-ytp"), "watch:player");
    } else if (kind === "shorts") {
      const actions = document.querySelector("ytd-reel-video-renderer[is-active] #actions, ytd-reel-video-renderer[is-active] reel-action-bar-view-model");
      place(actions, () => iconButton("omatube-round"), "shorts:actions");
    } else if (kind === "music") {
      place(document.querySelector("ytmusic-player-bar .right-controls-buttons, ytmusic-player-bar .middle-controls-buttons"),
        () => iconButton("omatube-music"), "music:bar");
    }
    applyMarks();
  }

  // YouTube mutates the DOM constantly; re-check the slots at most four times a second.
  let scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(() => { scheduled = false; ensure(); }, 250);
  }

  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener("yt-navigate-finish", () => { closeMenu(); if (thumbButton) thumbButton.hidden = true; refreshQueue(); schedule(); });

  chrome.storage.sync.get(DEFAULTS).then(stored => { settings = { ...DEFAULTS, ...stored }; ensure(); refreshQueue(); });
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "sync") return;
    for (const [key, { newValue }] of Object.entries(changes)) settings[key] = newValue ?? DEFAULTS[key];
    removeAll(); ensure();
  });

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type !== "trigger") return false;
    const available = Boolean(currentVideoId() && videoElement());
    if (available) send(message.action || settings.defaultAction);
    sendResponse({ ok: available });
    return false;
  });
})();
