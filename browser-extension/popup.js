localizePage();

document.getElementById("settings").addEventListener("click", () => chrome.runtime.openOptionsPage());

(async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const video = tab?.url ? OmaTubeTime.parseVideoUrl(tab.url) : null;
  const buttons = document.querySelectorAll("#actions button");
  buttons.forEach(button => {
    button.disabled = !video;
    button.addEventListener("click", async () => {
      buttons.forEach(row => { row.disabled = true; });
      const response = await chrome.runtime.sendMessage({ type: "trigger-tab", tabId: tab.id, action: button.dataset.action });
      if (response?.ok) window.close();
      else buttons.forEach(row => { row.disabled = false; });
    });
  });
  document.getElementById("no-tab").hidden = Boolean(video);

  const { lastError } = await chrome.storage.session.get("lastError");
  if (lastError) {
    document.getElementById("last-error").hidden = false;
    document.getElementById("last-error-text").textContent = lastError.message;
    // Shown once: the badge only signals an error the user has not seen yet.
    await chrome.storage.session.remove("lastError");
    await chrome.action.setBadgeText({ text: "" });
  }

  const response = await renderStatus(document.getElementById("status"));
  const current = response?.ok ? response.result.current : null;
  document.getElementById("playing").hidden = !(response?.ok && response.result.backend === "up");
  document.getElementById("playing-title").textContent = current?.title || t("popupNothing");
  document.getElementById("playing-author").textContent = current?.author || "";
})();
