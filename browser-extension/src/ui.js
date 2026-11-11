// Shared by popup and options: localization and the connection status line.
const t = (key, ...subs) => chrome.i18n.getMessage(key, subs.map(String)) || key;

function localizePage() {
  document.documentElement.lang = chrome.i18n.getUILanguage().split("-")[0];
  for (const node of document.querySelectorAll("[data-i18n]")) node.textContent = t(node.dataset.i18n);
  for (const node of document.querySelectorAll("[data-i18n-title]")) node.title = t(node.dataset.i18nTitle);
}

const SETTINGS_DEFAULTS = {
  defaultAction: "now", afterTransfer: "close", rewind: 3, placement: "actions",
  shorts: true, music: true, contextMenu: true, thumbnails: true,
};

// Fills a `.status` block from a hello response; returns the response for further use.
async function renderStatus(root) {
  const dot = root.querySelector(".dot"), label = root.querySelector(".status-label"), hint = root.querySelector(".status-hint");
  dot.className = "dot"; label.textContent = t("popupChecking"); hint.hidden = true;
  const response = await chrome.runtime.sendMessage({ type: "hello" });
  if (!response?.ok) {
    const missing = ["host_missing", "host_forbidden"].includes(response?.error?.code);
    dot.classList.add("err");
    label.textContent = missing ? t("popupMissing") : response?.error?.message || t("errGeneric", "?");
    if (missing) {
      hint.hidden = false;
      hint.replaceChildren(document.createTextNode(`${t("popupSetupHint")} `), Object.assign(document.createElement("code"), { textContent: "omatube browser-setup" }));
    }
    return response;
  }
  const result = response.result;
  if (result.backend !== "up") { dot.classList.add("warn"); label.textContent = t("popupDown"); }
  else if (result.accept === false) { dot.classList.add("warn"); label.textContent = t("popupDisabled"); }
  else { dot.classList.add("ok"); label.textContent = result.browserName ? t("popupOkVia", result.browserName) : t("popupOk"); }
  const own = chrome.runtime.getManifest().version;
  if (result.hostVersion && result.hostVersion !== own) {
    hint.hidden = false; hint.textContent = t("popupVersionMismatch", own, result.hostVersion);
  }
  return response;
}
