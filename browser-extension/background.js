// Firefox loads lib/time.js from manifest background.scripts; Chromium's service worker imports it.
if (typeof importScripts === "function") importScripts("lib/time.js");

const HOST = "com.vornashev.omatube";
const LINK_MENU = "omatube-link";
const CLOSE_DELAY_MS = 900;
const LINK_PATTERNS = [
  "https://www.youtube.com/watch*", "https://m.youtube.com/watch*", "https://music.youtube.com/watch*",
  "https://www.youtube.com/shorts/*", "https://youtube.com/watch*", "https://youtu.be/*",
];
const DEFAULTS = {
  defaultAction: "now", afterTransfer: "close", rewind: 3, placement: "actions",
  shorts: true, music: true, contextMenu: true, thumbnails: true,
};

const settings = async () => ({ ...DEFAULTS, ...(await chrome.storage.sync.get(DEFAULTS)) });
const t = (key, ...subs) => chrome.i18n.getMessage(key, subs.map(String)) || key;

function browserName() {
  const gecko = navigator.userAgent.match(/(LibreWolf|Waterfox|Zen|Firefox)\/[\d.]+/);
  if (gecko && !navigator.userAgentData) return gecko[1];
  const brands = navigator.userAgentData?.brands?.map(row => row.brand) ?? [];
  return brands.find(brand => !/Not.?A.?Brand|Chromium/i.test(brand)) || brands.find(brand => /Chromium/i.test(brand)) || "Chromium";
}

// Errors reported by Chromium itself, before the host gets to answer.
function hostError(message = "") {
  if (/not found|no such native application/i.test(message)) return { code: "host_missing", message: t("errHostMissing") };
  if (/forbidden/i.test(message)) return { code: "host_forbidden", message: t("errHostForbidden") };
  if (/exited|disconnected/i.test(message)) return { code: "host_crashed", message: t("errHostCrashed") };
  return { code: "provider_error", message: t("errGeneric", message || "?") };
}

// The host's own error codes, with a localized message where we have one.
function localize(error) {
  const known = { backend_down: "errBackendDown", disabled: "errDisabled" };
  return known[error?.code] ? { ...error, message: t(known[error.code]) } : error;
}

async function native(message) {
  const payload = { ...message, extensionVersion: chrome.runtime.getManifest().version, browser: browserName() };
  try {
    const response = await chrome.runtime.sendNativeMessage(HOST, payload);
    if (!response || typeof response !== "object") return { ok: false, error: hostError() };
    return response.ok ? response : { ok: false, error: localize(response.error) };
  } catch (error) {
    return { ok: false, error: hostError(error?.message) };
  }
}

async function rememberError(error) {
  await chrome.storage.session.set({ lastError: error ? { ...error, at: Date.now() } : null });
  await chrome.action.setBadgeText({ text: error ? "!" : "" });
  if (error) await chrome.action.setBadgeBackgroundColor({ color: "#d93025" });
}

// `keepTab`: the video came from a thumbnail, not from the tab's own player, so the tab stays.
async function transfer(payload, tab, keepTab = false) {
  const response = await native({ type: "transfer", ...payload });
  await rememberError(response.ok ? null : response.error);
  if (response.ok && !keepTab && tab?.id !== undefined && (await settings()).afterTransfer === "close") {
    setTimeout(() => chrome.tabs.remove(tab.id).catch(() => {}), CLOSE_DELAY_MS);
  }
  return response;
}

// Ask the tab's content script to collect the position and send; inject it first on tabs
// that were open before the extension was (re)loaded.
async function triggerTab(tabId, action) {
  const message = { type: "trigger", action };
  try { return await chrome.tabs.sendMessage(tabId, message); }
  catch (_) {
    await chrome.scripting.insertCSS({ target: { tabId }, files: ["content.css"] });
    await chrome.scripting.executeScript({ target: { tabId }, files: ["lib/time.js", "content.js"] });
    return chrome.tabs.sendMessage(tabId, message);
  }
}

async function syncMenus() {
  await chrome.contextMenus.removeAll();
  if (!(await settings()).contextMenu) return;
  chrome.contextMenus.create({ id: LINK_MENU, title: t("ctxLink"), contexts: ["link"], targetUrlPatterns: LINK_PATTERNS });
}

chrome.runtime.onInstalled.addListener(syncMenus);
chrome.runtime.onStartup.addListener(syncMenus);
chrome.storage.onChanged.addListener((changes, area) => { if (area === "sync" && changes.contextMenu) syncMenus(); });

chrome.contextMenus.onClicked.addListener(async info => {
  if (info.menuItemId !== LINK_MENU) return;
  const link = OmaTubeTime.parseVideoUrl(info.linkUrl);
  if (!link) return;
  // A link is not a playing tab: nothing to close, the timestamp comes from the link itself.
  const response = await native({ type: "transfer", videoId: link.videoId, start: link.start, action: (await settings()).defaultAction });
  await rememberError(response.ok ? null : response.error);
});

chrome.commands.onCommand.addListener(async command => {
  if (command !== "send-to-omatube") return;
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url || !OmaTubeTime.parseVideoUrl(tab.url)) return;
  triggerTab(tab.id, (await settings()).defaultAction).catch(() => {});
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (sender.id !== chrome.runtime.id) return false;
  if (message?.type === "transfer") {
    transfer(message.payload, sender.tab, Boolean(message.keepTab)).then(sendResponse);
    return true;
  }
  if (message?.type === "queue" || message?.type === "unqueue" || message?.type === "queue_move") {
    native({ type: message.type, videoId: message.videoId, placement: message.placement }).then(sendResponse);
    return true;
  }
  if (message?.type === "hello") {
    native({ type: "hello" }).then(sendResponse);
    return true;
  }
  if (message?.type === "trigger-tab") {
    triggerTab(message.tabId, message.action).then(sendResponse, error => sendResponse({ ok: false, error: hostError(error?.message) }));
    return true;
  }
  return false;
});
