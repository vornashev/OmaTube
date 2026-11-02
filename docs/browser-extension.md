<!-- markdownlint-disable MD013 -->

# Browser extension

The bundled **Watch in OmaTube** extension sends videos from YouTube in your browser to OmaTube.

## What it does

- A **Watch in OmaTube** button on YouTube, Shorts and YouTube Music. It pauses the video and puts it at the head of My queue in OmaTube, starting from the same moment. Then it closes the tab. Whatever was playing moves to second place and later resumes where it stopped.
- The arrow next to the button offers **Play next** (right after the current video) and **Play last** (end of My queue).
- `Alt+Shift+O` and a link context-menu item do the same as the button.
- Hovering a thumbnail anywhere on YouTube (feed, search, sidebar) shows a small OmaTube button in its corner. A click adds the video to the end of My queue without leaving the page. A right-click offers **Play now** and **Play next**.
- Videos already in the OmaTube queue are marked on thumbnails with their place (Next, Playing or a number, with time to start in the tooltip). Click a mark to remove the video from the queue.

## Supported browsers

| Family | Browsers |
| --- | --- |
| Chromium | Chromium (the Omarchy default), Google Chrome (stable, beta, dev), Brave, Vivaldi, Microsoft Edge, Opera, Thorium, Helium, Yandex Browser |
| Gecko | Firefox 128+, Zen, LibreWolf, Floorp, Waterfox |

You can use several browsers at once; they share one OmaTube queue. Flatpak and Snap builds are reported as unsupported because their sandbox cannot start the bridge.

## Install

The installer copies the extension to `~/.local/share/omatube/browser-extension` and registers the native messaging host for every browser it finds. OmaTube repeats the registration on every service start, so it also picks up browsers you install later. To register right away, run `omatube browser-setup`.

### Chromium-based browsers

1. Open `chrome://extensions` (or your browser's equivalent).
2. Enable **Developer mode**.
3. Click **Load unpacked** and choose `~/.local/share/omatube/browser-extension`.
4. After updating OmaTube, press **Reload** on the extension card.

### Firefox and forks

The installer also builds a Firefox flavour of the extension from the same sources. Each GitHub release attaches the same `.xpi`.

Release Firefox only installs signed add-ons, so pick one of these:

- **Temporary (until restart):** open `about:debugging` → **This Firefox** → **Load Temporary Add-on** and choose `~/.local/share/omatube/browser-extension-firefox/manifest.json`.
- **Permanent:** in Firefox Developer Edition, Nightly or LibreWolf with `xpinstall.signatures.required` set to `false`, choose **Install Add-on From File** in `about:addons` and pick `~/.local/share/omatube/omatube-firefox.xpi`.

### A browser that isn't listed

```bash
omatube browser-setup --dir <profile folder>                   # Chromium-based
omatube browser-setup --dir <profile folder> --family gecko    # Firefox fork
omatube browser-setup --forget <profile folder>                # undo
```

## Settings

- **In the extension** (its options page): default action, close or keep the tab after a transfer, rewind 0–10 s, button placement (below the video, in the player bar or both), Shorts, YouTube Music, the link menu item and the thumbnail button.
- **In OmaTube** (Settings → Browser): accept videos from the browser, video mode for transferred videos, desktop notification, bridge status per browser and reinstalling the bridge.

Settings → Browser shows one row per browser with one of these statuses: connected (with time and extension version), reload the extension, not connected yet, bridge missing (with an **Install** button) or not supported.

## How the bridge works

The extension talks to a small native host, `omatube-native-host`, over native messaging. No network port is opened. The host accepts only a fixed set of messages (status, transfer, and reading or reordering the queue), so the extension cannot run any other backend command. If `omatube.service` is not running, the host starts it.

The host identifies the browser that started it from its parent process and records the last-seen time and extension version for each browser in `~/.local/share/omatube/browser-link.json`.

```bash
omatube browser-status            # one JSON row per browser
omatube browser-setup             # register for all detected browsers
omatube browser-setup --remove    # unregister everywhere
```
