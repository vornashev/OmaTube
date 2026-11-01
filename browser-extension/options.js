localizePage();

const REWIND_CHOICES = [0, 3, 5, 10];
const rewind = document.getElementById("rewind");
for (const value of REWIND_CHOICES) {
  const label = document.createElement("label");
  const input = Object.assign(document.createElement("input"), { type: "radio", name: "rewind", value: String(value) });
  const text = document.createElement("span");
  text.textContent = value ? t("optSeconds", value) : t("optNone");
  label.append(input, text);
  rewind.append(label);
}

let savedTimer = null;
function flashSaved() {
  const node = document.getElementById("saved");
  node.classList.add("shown");
  clearTimeout(savedTimer);
  savedTimer = setTimeout(() => node.classList.remove("shown"), 1200);
}

async function save(key, value) {
  await chrome.storage.sync.set({ [key]: value });
  flashSaved();
}

(async () => {
  const settings = { ...SETTINGS_DEFAULTS, ...(await chrome.storage.sync.get(SETTINGS_DEFAULTS)) };
  for (const group of document.querySelectorAll(".choices[data-setting]")) {
    const key = group.dataset.setting;
    for (const input of group.querySelectorAll("input")) {
      input.checked = input.value === String(settings[key]);
      input.addEventListener("change", () => save(key, key === "rewind" ? Number(input.value) : input.value));
    }
  }
  for (const input of document.querySelectorAll("input[type=checkbox][data-setting]")) {
    const key = input.dataset.setting;
    input.checked = Boolean(settings[key]);
    input.addEventListener("change", () => save(key, input.checked));
  }
})();

async function renderShortcut() {
  const command = (await chrome.commands.getAll()).find(row => row.name === "send-to-omatube");
  document.getElementById("shortcut").textContent = t("optShortcutCurrent", command?.shortcut || t("optShortcutNone"));
}
// Firefox has its own shortcut page and does not let extensions open about:addons directly.
document.getElementById("shortcut-change").addEventListener("click", () => chrome.commands.openShortcutSettings
  ? chrome.commands.openShortcutSettings() : chrome.tabs.create({ url: "chrome://extensions/shortcuts" }));
addEventListener("focus", renderShortcut);
renderShortcut();

const status = document.getElementById("status");
document.getElementById("check").addEventListener("click", () => renderStatus(status));
renderStatus(status);
