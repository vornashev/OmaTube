<!-- markdownlint-disable MD013 MD024 -->

# Changelog

All notable changes to OmaTube are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). New entries go under **Unreleased**; `scripts/release.sh` turns that section into a dated release.

## [Unreleased]

## [0.3.0] - 2026-11-14

### Changed

- OmaTube needs nothing beyond a stock Omarchy. Deno now comes from a pinned wheel in `requirements.lock`, and the catalog worker runs on it instead of Node.js, so Node.js, npm and a system Deno are no longer required. npm packages install with `deno install --frozen` from `deno.lock`, at the same versions and integrity hashes as before.
- The catalog worker runs in Deno's permission sandbox: network access, read and write in one scratch directory under `$XDG_RUNTIME_DIR/omatube`, and three temp-directory variables. It cannot read your files or start programs.
- The backend is no longer a systemd user service. `omatube start` launches it as a user process in a session of its own; the widget, the browser bridge and the installer start it when they need it, and a lock keeps one instance. It survives shell restarts as before. mpv, yt-dlp and the catalog worker exit with it, even after a crash. The widget restarts a backend that died. The update removes the old unit automatically.
- New commands: `omatube start`, `omatube stop`, `omatube restart` and `omatube logs [-f]`. The log is at `~/.local/state/omatube/backend.log`.
- A proxy is set in `~/.config/omatube/proxy`. The update moves an `OMATUBE_PROXY` set in a drop-in for the old unit there.

### Removed

- The hardened service sandbox: the backend now has normal user permissions. The catalog worker keeps a sandbox of its own (see above).

## [0.2.1] - 2026-11-11

### Changed

- The browser extension source moved to `browser-extension/src/` so the repository carries a single plugin manifest, as the Omarchy plugin marketplace requires. The installed extension stays at `~/.local/share/omatube/browser-extension`; nothing needs reloading.
- The manifest declares the MIT license, and the marketplace preview sits at the repository root as `preview.png`.

### Fixed

- The widget receives state changes over a persistent local connection instead of launching a status command repeatedly; playback position updates no longer invalidate unrelated UI bindings.
- Inactive pages are released after ten minutes and restore their navigation, filters and scroll position on return. History, subscription feeds and channel grids create only rows/cards near the viewport.
- Catalog, feed-response, lyrics and stream caches have byte budgets and expiry cleanup, reducing retained memory during long sessions.
- The panel and its pages are created on first use and retain their state afterwards; covers decode at a size matched to the display, reducing memory use without blurring thumbnails on scaled monitors.
- Hidden equalizers, loading indicators and scrolling bar titles stop animating when their item or window is hidden, reducing background CPU use.

### Security

- Titles, channel names and other text from YouTube render as plain text. Before, a title containing HTML could make the shell load a remote image and reveal your IP address.
- The backend, the browser bridge, the installer and the widget run external programs (mpv, Node.js, Deno, ffmpeg, systemctl, wl-copy, xdg-open) only from `/usr/bin` and `/usr/local/bin`, never from earlier entries in your `PATH`.

## [0.2.0] - 2026-11-02

### Highlights

- **My queue.** Single videos now go to a separate, persistent queue. Playlists, albums and radio play in **Now playing**. A playlist you interrupt with a video resumes from the same track and second.
- **New pages.** History, Statistics, Subscriptions with an RSS feed, Channel and Playlist pages, Downloads and saved queue sessions. Home recommendations now appear on the empty search page.
- **Browser extension for any browser.** “Watch in OmaTube” works in 16 Chromium and Firefox-based browsers, including several at once, and marks queued videos on YouTube thumbnails.
- **Wide, compact and shelf layouts.** A new player with a chapter timeline, storyboard previews, SponsorBlock segments, synced lyrics and comments.
- **English and Russian interface.** The language follows the system locale.

### Added

#### Playback and queue

- My queue: a persistent list of single videos and podcasts, separate from Now playing. Each item resumes from its saved position, finished items leave the list with a restore toast, and when a playlist ends playback continues with My queue. The rail pins My queue above playlists.
- One rule for Play in the plugin and the browser: a single video (search, Home, Subscriptions, History, library, channel, a pasted link) goes to the head of My queue and starts. The interrupted item moves to second place. Lists (playlists, albums, Play all, radio, sessions) fill Now playing. A playlist paused for a video resumes from the same track and second; a toast can put the finished video back.
- Queue sessions: save, restore, append and delete, plus a “restore queue on start” setting.
- Queue rows: the number turns into ▶ on hover; drag handle; play next, save, remove and more on hover or keyboard focus; played rows dimmed with ✓; a NEXT badge with time to start; NEW flash for added rows. Drag-and-drop reordering, Ctrl/Shift selection with bulk actions, and undoable removal (Ctrl+Z). Shortcuts: Enter, N, S, Delete, Alt+↑/↓.
- Playback options popover: mode, video quality, speed, sleep timer, loudness normalization and silence skipping.
- SponsorBlock: per-category skip / ask / off, coloured segments on the timeline, a “Skipped · Undo” toast and a “sponsor in 3 s · don't skip” tag.
- Synced lyrics from LRCLIB with click-to-seek and a ±0.5 s offset.
- Chapters and description tabs with clickable timestamps; chapter ticks on the timeline.
- Stream pre-resolution on hover (Settings → “Prepare the stream on hover”), a larger mpv demuxer cache and a “slow network” badge when recent requests are slow or failing.

#### Pages and layouts

- Wide 1100×660 panel with a navigation rail, player card and queue pane; compact (420 px) and shelf (1440×236) formats selectable in Settings.
- Thin player outside the Now tab: a 3 px timeline that grows on hover, chapter gaps, SponsorBlock colours, storyboard preview with time delta and chapter, drag with Esc to cancel, ←/→ ±10 s, Shift ±1 min, `[` `]` for chapters, wheel ±5 s, and a sheet with chapters, queue and description. A full bottom player is available as an alternative.
- Search results as a 16:9 card grid with a grid/list toggle. The empty search page shows recent queries (up to 8, only while history is on), Continue watching, New from subscriptions and Recommended; Esc in the search field returns there.
- History page grouped by day, with resume, removal and filters.
- Statistics page: listening time per day, 5 days and month, SponsorBlock savings, top channels and tracks.
- Subscriptions: local channel subscriptions with an RSS feed (no sign-in needed), “new” badges and watch-progress marks, plus import of subscriptions from a signed-in YouTube account.
- Channel page with Videos, Playlists, Shorts, Podcasts and Live tabs, Newest/Popular sorting, banner, subscribe and Play all. Open it from the author in the player, a card, a row menu or a channel result.
- Playlist page with a cover mosaic and play, shuffle and enqueue actions; its main button follows the list state (play, starting, pause, continue, replace queue, resume from track N).
- Downloads of audio (Opus) or video (MP4) to `~/Videos/OmaTube` with pause, retry, cancel and open-folder actions. The rail shows overall progress and failed downloads.
- Settings page with groups, a live bar preview and bar layouts (icon, icon + title, full), idle hiding, mouse-wheel volume and bar states for pause, buffering, error and resolution. First-run onboarding screen.
- Row menu actions: add to playlist, copy link and timestamped link, open in browser, Watch later, Radio, Go to channel and Don't recommend channel.
- Playback states everywhere: rows and cards show loading, playing, paused, queued, watched, unavailable and error with retry.
- Toasts with undo for enqueue, play next, save, add to playlist, copy link and failed starts.
- English and Russian interface with a language switch in Settings → Language (`language` preference: `auto`, `en`, `ru`). `auto` follows the system locale and falls back to English. Backend errors, default playlist names and the native-host notification are translated too.

#### Browser extension

- “Watch in OmaTube” button on YouTube, Shorts and YouTube Music. It pauses the video, sends it to OmaTube at the same moment (with optional rewind; ads are skipped over) and closes the tab. Play next and Play last in the menu, an `Alt+Shift+O` shortcut, a link context-menu item and a hover button on thumbnails that queues without leaving the page.
- Videos already in the OmaTube queue are marked on thumbnails with their place (Next, Playing or a number, with time to start). The marks stay correct across reloads and as the queue moves.
- Bridge for 16 Chromium and Gecko browsers and several at once: registration on every service start, `omatube browser-setup --dir/--forget` for browsers outside the list, and Flatpak/Snap builds reported as unsupported. Settings → Browser shows one row per browser with its status and an Install button.
- Firefox 128+, Zen and LibreWolf: the installer builds `omatube-firefox.xpi` and an unpacked copy for `about:debugging`.
- `omatube-native-host` native messaging bridge with a fixed message whitelist that starts the backend on demand, plus `omatube browser-setup [--remove]` and `omatube browser-status`.

#### Backend

- Two playback lanes in the player state (`lane`, `lanes`; single-queue states migrate). `queue_remove`, `queue_move`, `queue_restore` and `queue_clear` take an optional `lane`; new `lane_switch` command.
- `play_url` and `enqueue_url` accept `start` (and honour `t=` in links) and metadata hints.
- Queue context (“N of M” for playlists), per-playlist resume (`play_playlist` with `resume`), `cancel_load`, `sponsor_keep`, timeline storyboards from yt-dlp.
- Pooled keep-alive HTTP client with ETag revalidation for RSS, SponsorBlock and LRCLIB; TLS and mpv warm-up at start.
- Loopback thumbnail cache (`127.0.0.1:47865`, 256 MB LRU on disk, allow-listed image hosts, proxy-aware) with fallback to direct loading.
- Catalog response cache in the worker (search 3 min, channels 5 min, comments 10 min, suggestions 30 min) with stale-if-error fallback for up to 24 h.
- Slow read commands (comments, lyrics, feed, downloads) run in a parallel lane and no longer block playback controls.
- Status reports `downloadsFailed` and `downloadsProgress`; preferences gain `panelFormat`, `searchView`, `onboarded`, `normalize`, `skipSilence`, `language` and `recentSearches`.

### Changed

- The shell UI moved from the repository root to `ui/` (`entryPoints.barWidget` is now `ui/BarWidget.qml`). `omarchy plugin update` and `install.sh` remove the old files.
- Errors no longer cover the top of the page. Backend, catalog and playback failures appear as a toast with Retry, Copy and Dismiss (and Account for sign-in errors). A library or playlist that failed to refresh keeps the previous list with a NOT UPDATED tag; with nothing to show, the error replaces the list.
- The rail footer replaces Home with a Downloads button next to Subscriptions.
- Visual pass against the design: Lucide icons, outlined controls, underlined tabs and consistent sizes.
- Release notes on GitHub now come from this changelog, and each release ships the Firefox `.xpi` and a `SHA256SUMS` file.
- README shows screenshots of the panel formats and pages, plus a marketplace preview image (`docs/screenshots/`).

### Fixed

- YouTube cookie import reads Chromium's own keyring item. Before, yt-dlp could pick another app's “Chromium Safe Storage” key and return guest cookies.
- Play/pause icons return to an upright position after loading; only the loading indicator rotates.
- The playback options menu stays attached to its button across layout changes, and a second click closes it.
- The no-account choice on the onboarding screen shows its icon.
- `install.sh` from a clone copied a fixed list of QML files and missed new ones.

### Removed

- Library tabs “YouTube” and “Authors” (entity bookmarks). Nothing in the UI could add to them, and they duplicated Playlists and Subscriptions. The `save_entity` command and the `bookmarks`/`authors` collection sections are gone; on upgrade, saved channels and artists become subscriptions and saved playlists become YouTube playlists (database version 9).
- The new-subscription dot on the bar cover.

## [0.1.1] - 2026-09-09

### Added

- One-command installation and enablement through `omarchy plugin add`.
- Automatic first-load backend setup and version-aware service startup.

## [0.1.0] - 2026-09-09

### Added

- Native Omarchy Shell bar widget with compact playback controls and a full popup interface.
- YouTube and YouTube Music search, suggestions, paginated results, and entity browsing.
- Audio, tiled-video, and floating-video playback through mpv, including selectable video quality.
- Persistent queue with seeking, volume, mute, shuffle, repeat, and automatic continuation.
- Local saved media, bookmarks, history, editable playlists, and public-playlist copying.
- Optional Chromium cookie import for authenticated and restricted YouTube content.
- MPRIS integration and a Unix-socket CLI for status, details, and backend requests.
- Reproducible locked Python and Node.js dependencies with an explicit youtubei.js compatibility patch.
- Hardened systemd user service, installer, updater-compatible layout, and data-preserving uninstaller.
- Recovery for mpv disconnects, stale events, stream failures, buffering transitions, and interrupted playback.
- Automated tagged releases containing a versioned source archive and SHA-256 checksum.

### Changed

- Media-row hover covers its actions and exposes playlist-copy controls from search details.
- Player header and panel expose video mode, quality, authentication status, and configurable bar content.
- Stream resolution supports authenticated cookies, separate audio/video tracks, and bounded quality selection.

[Unreleased]: https://github.com/vornashev/OmaTube/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/vornashev/OmaTube/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/vornashev/OmaTube/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/vornashev/OmaTube/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/vornashev/OmaTube/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/vornashev/OmaTube/releases/tag/v0.1.0
