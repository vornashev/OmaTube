<!-- markdownlint-disable MD013 MD024 -->

# Changelog

All notable changes to OmaTube are documented in this file. Versions follow [Semantic Versioning](https://semver.org/), and release dates use `YYYY-MM-DD`.

[Русская версия](#русский)

## [0.2.0] - Unreleased

### Added

- My queue: a persistent list of videos and podcasts saved for later, separate from what "Play" starts. Playing a playlist no longer wipes it; it is pinned at the top of the rail's playlists, and clicking it switches playback there. Each item resumes from its saved position, finished items leave the list (with a restore toast), and when a playlist ends playback continues with My queue. "Add to queue" actions and the browser extension save to My queue; "Play next" still targets what is playing. The player state keeps both lanes (`lane`, `lanes`; older single-queue states migrate), and `queue_remove`/`queue_move`/`queue_restore`/`queue_clear` accept an optional `lane`, plus a new `lane_switch` command.
- English and Russian interface with a language switch in Settings → Язык / Language (`language` preference: `auto`, `en`, `ru`). `auto` follows the system locale and falls back to English when the system language is not supported. UI strings live in `i18n.js` (Russian source text is the key); backend error messages, default playlist names and the native-host notification are translated too.
- Browser extension for Firefox 128+, Zen and LibreWolf: the installer builds `~/.local/share/omatube/omatube-firefox.xpi` (plus an unpacked copy for `about:debugging`) from the same sources, and `omatube browser-setup` registers the native host for Firefox, Zen and LibreWolf (Gecko reads `~/.mozilla` even when the profile lives in `~/.config`).
- Browser bridge for any browser and several at once: a table of 16 Chromium and Gecko browsers (installed = has a profile, not just a folder), automatic re-registration on every service start, `omatube browser-setup --dir/--forget` for browsers outside the table, and Flatpak/Snap builds reported as unsupported. The native host names the browser that started it (from its parent process) and keeps last seen and extension version per browser; Settings → Browser shows one row per browser with its status and an Install button, and the popup says “Connected via Zen”.
- Browser extension: "Play now" (the main button) puts the video at the head of My queue and starts it at once; what was playing moves to second place and resumes later, and a copy already in My queue is moved instead of duplicated. "Add to queue" is renamed "Play last"; "Play next" into an idle queue goes first. The main button's icon follows the configured action, and the menu is dark on YouTube's dark theme.
- Browser extension: videos already in the OmaTube queue are marked on YouTube thumbnails with their place ("Next" / "Playing" / number, with time to start in the tooltip; click removes) and in the watch-page button. The queue is read from OmaTube through the native host (`queue`, `unqueue`), so marks survive reloads and update as the queue moves.
- History page (grouped by day, resume from where you stopped, remove entries, filters), Home page (continue watching, new in subscriptions, radio-based recommendations from your history), Statistics page (listening time per day/5 days/month, SponsorBlock savings, top channels and tracks), and queue sessions (save, restore, append, delete; "restore queue on start" setting).
- Compact (420px) layouts for Subscriptions, Downloads, Channel and Playlist pages; Subscriptions and Downloads join the compact tab bar.
- Import of YouTube subscriptions from the signed-in account (`subscriptions_import`, yt-dlp `feed/channels` with the stored cookies).
- Network layer: pooled keep-alive HTTP client with ETag revalidation for RSS feeds, SponsorBlock and LRCLIB; warm-up of TLS connections and the idle mpv process at start.
- Thumbnails are served through a loopback image cache (`127.0.0.1:47865`, disk LRU 256 MB under `~/.local/share/omatube/cache/images`, proxy-aware, small cards get 320px variants) with automatic fallback to direct loading.
- Catalog response cache in the worker (search 3 min, channels 5 min, comments 10 min, suggestions 30 min) with fresh cursors per hit and stale-if-error fallback for up to 24 h.
- Stream pre-resolution when hovering a video (setting "Готовить поток при наведении"), larger mpv demuxer cache, and a "медленная сеть" badge when recent requests are slow or failing.
- YouTube cookie import now reads Chromium's own keyring item (yt-dlp could pick another app's "Chromium Safe Storage" key and return guest cookies).
- Wide 1100×660 panel: navigation rail, player card with cover, volume and mode actions, queue pane, plus a compact format selectable in settings.
- Search results as a 16:9 card grid with a grid/list toggle.
- Settings page (panel format, bar widget options, history, YouTube account) and a first-run onboarding screen.
- `panelFormat` (wide / compact / shelf), `searchView`, `onboarded`, `normalize` and `skipSilence` preferences.
- Playback options popover: mode, video quality, speed, sleep timer, loudness normalization and silence skipping.
- Queue pane tabs for chapters and description with clickable timestamps; chapter ticks on the progress bar.
- Row context menu with playlist, copy link and open in browser; clipboard hint on an empty queue; keyboard-layout fix for empty searches; account shortcut on authentication errors.
- Playlist picker popup, playback error card with retry/skip, loading spinner and a mini player for compact pages.
- Settings page with groups, live bar preview and bar layouts (icon / icon + title / full), idle hiding and mouse-wheel volume; bar states for pause, buffering, error and video resolution.
- SponsorBlock: per-category skip / ask / off, coloured segments on the progress bar, "Skipped · Undo" toast.
- Subscriptions: local channel subscriptions with an RSS feed (no sign-in), channel page with subscribe / play all / tabs, "new" badges, watch-progress marks and a "new" dot in the bar.
- Synced lyrics from LRCLIB with click-to-seek and a ±0.5 s offset.
- Downloads: audio (opus) or video (mp4) through yt-dlp into `~/Videos/OmaTube` with pause, retry, cancel and open-folder actions.
- Chapter tabs, comments tab, "Watch later", "Radio", timestamped link, "Go to channel" and "Don't recommend channel" row actions.
- Slow read commands (comments, lyrics, feed, downloads) run in a parallel lane so they no longer block playback controls.
- UI pass against the design: lucide icons, outlined controls, underlined tabs, design font sizes and paddings across all screens.
- Channel navigation: click the author in the player, a card, a row menu or a channel result to open the channel page with Videos / Playlists / Shorts / Podcasts / Live tabs, Newest / Popular sorting, banner, subscribe and "channel playlists".
- Shelf panel format (1440×236) and a playlist page with cover mosaic and play / shuffle / enqueue actions.
- “Watch in OmaTube” browser extension for Chromium, Chrome, Brave, Vivaldi and Edge. It sends the video to OmaTube at the current position (with optional rewind; ads are skipped over) and closes the tab. It also offers “Play next”, “Add to queue”, an `Alt+Shift+O` shortcut, a link context-menu item, buttons on Shorts and YouTube Music, and a hover button on video thumbnails that adds the video to the queue without leaving the page.
- `omatube-native-host` native messaging bridge with a fixed message whitelist that starts the backend on demand, plus the `omatube browser-setup [--remove]` and `omatube browser-status` commands.
- `play_url` / `enqueue_url` accept `start` (and honour `t=` in links) and display metadata hints; queued entries keep their start position until played.
- Settings → Browser: accept videos from the browser, video mode for transferred videos, transfer notification, bridge status and reinstall.
- Player outside «Сейчас» in the wide panel: a thin panel (default) with a 3 px timeline that grows to 8 px on hover, chapter gaps, SponsorBlock colours, storyboard frame preview with time delta and chapter, drag with a ghost mark (Esc cancels), click on a chapter gap, ←/→ ±10 s, Shift ±1 min, [ ] chapters, wheel ±5 s, and a "sponsor in 3 s · don't skip" tag; ˄ opens a sheet over the current tab with chapters, queue and description. A full bottom panel is available as an alternative (setting "Плеер вне «Сейчас»").
- Playback states everywhere: rows show loading (spinner, running stripe, cancel), playing (accent bar, equalizer, position), paused, watched, unavailable and error with retry; cards show loading, "ИГРАЕТ"/"ПАУЗА"/"В ОЧЕРЕДИ · N" badges and progress; the playlist main button follows the list (play / starting / pause / continue / replace queue / resume from track N) with a status line, and the rail marks the playing playlist.
- Toasts with undo for actions that stay on the same screen: enqueue, play next, save, add to playlist, copy link, failed start with retry.
- Backend: queue context (`context` with "N of M" for playlists), per-playlist resume position (`play_playlist` with `resume`), `cancel_load`, `sponsor_keep`, `upcoming` SponsorBlock segment, enqueue position, and timeline storyboards from yt-dlp.
- Queue rows redesigned: number turns into ▶ on hover, a drag handle and four actions (play next, save, remove, more) appear on hover and keyboard focus; played rows are dimmed with ✓, the next one carries a "ДАЛЕЕ" badge with time to start, new rows flash with a "НОВОЕ" badge. Drag-and-drop reordering, Ctrl/Shift-click selection with bulk actions, and removal that collapses into a 5-second "Вернуть" plaque (Ctrl+Z works too). Shortcuts: Enter, N, S, Delete, Alt+↑/↓. Backend `queue_restore` puts removed entries back in place.

### Fixed

- Play/pause icons in the players, queue, media rows and playlist controls now reset to an upright position after loading; only the loading indicator rotates.
- Removed the new-subscription notification dot from the bar cover in all bar layouts.
- Playback options attach to the live toggle button and track panel layout changes; clicking the button again closes the menu instead of reopening it.

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

---

## Русский

Все заметные изменения OmaTube документируются в этом файле. Версии соответствуют [Semantic Versioning](https://semver.org/lang/ru/), даты релизов записываются в формате `ГГГГ-ММ-ДД`.

[English version](#changelog)

## [0.2.0] - В разработке

### Добавлено

- «Моя очередь»: постоянный список видео и подкастов на потом, отдельный от того, что запускает «Играть». Запуск плейлиста её больше не стирает; она закреплена первой строкой среди плейлистов, клик переключает воспроизведение на неё. Каждое видео продолжается с сохранённого места, досмотренное само уходит из списка (тост позволяет вернуть), а когда плейлист заканчивается, воспроизведение продолжается с «Моей очереди». «В очередь» и расширение браузера добавляют в «Мою очередь»; «Играть следующим» по-прежнему работает с тем, что играет сейчас.
- Расширение для Firefox 128+, Zen и LibreWolf: установщик собирает `~/.local/share/omatube/omatube-firefox.xpi` (и распакованную копию для `about:debugging`) из тех же исходников, а `omatube browser-setup` регистрирует native host для Firefox, Zen и LibreWolf (Gecko читает `~/.mozilla`, даже если профиль лежит в `~/.config`).
- Связка с любым браузером и с несколькими сразу: таблица из 16 браузеров на Chromium и Gecko (установленным считается браузер с профилем, а не просто папкой), автоматическая перерегистрация при каждом запуске сервиса, `omatube browser-setup --dir/--forget` для браузеров вне таблицы, сборки Flatpak/Snap помечаются как неподдерживаемые. Мост определяет запустивший его браузер по родительскому процессу и хранит время и версию расширения отдельно для каждого браузера; в «Настройки → Браузер» у каждого своя строка со статусом и кнопкой «Установить», а popup пишет «Подключено через Zen».
- Расширение: «Смотреть сейчас» (главная кнопка) ставит видео первым в «Мою очередь» и сразу включает; то, что играло, сдвигается на второе место и потом продолжится, а копия, уже стоящая в очереди, переносится, а не дублируется. «Следующим» в пустую очередь ставит первым. Иконка главной кнопки соответствует выбранному действию, меню на тёмной теме YouTube тоже тёмное.

### Исправлено

- Значки play/pause в плеерах, очереди, строках медиа и кнопках плейлиста после загрузки возвращаются в исходное положение; вращается только индикатор загрузки.
- Убрана точка новых публикаций над обложкой в баре во всех вариантах его отображения.
- Меню режима, скорости и таймера сна привязано к живой кнопке и следует за раскладкой панели; повторное нажатие закрывает меню, а не открывает его заново.

## [0.1.1] - 2026-09-09

### Добавлено

- Установка и включение одной командой `omarchy plugin add`.
- Автоматическая настройка бэкенда при первой загрузке и запуск сервиса с проверкой версии.

## [0.1.0] - 2026-09-09

### Добавлено

- Нативный виджет панели Omarchy Shell с компактным управлением и полноценным всплывающим интерфейсом.
- Поиск в YouTube и YouTube Music, подсказки, постраничная загрузка результатов и просмотр страниц сущностей.
- Воспроизведение аудио, тайлового и плавающего видео через mpv с выбором качества.
- Сохраняемая очередь с перемоткой, громкостью, отключением звука, перемешиванием, повтором и автоматическим продолжением.
- Локально сохранённые медиа, закладки, история, редактируемые плейлисты и копирование публичных плейлистов.
- Необязательный импорт cookies Chromium для авторизованного и ограниченного контента YouTube.
- Интеграция MPRIS и CLI через Unix-сокет для получения состояния, деталей и отправки команд бэкенду.
- Воспроизводимые зафиксированные зависимости Python и Node.js с явным патчем совместимости youtubei.js.
- Защищённый пользовательский сервис systemd, установщик, структура для обновлений и удаление с сохранением данных.
- Восстановление после отключений mpv, устаревших событий, ошибок потоков, буферизации и прерванного воспроизведения.
- Автоматические релизы по тегам с версионированным архивом исходного кода и контрольной суммой SHA-256.

### Изменено

- Область наведения строки медиа включает кнопки действий; в деталях поиска доступно копирование плейлиста.
- Заголовок проигрывателя и панель показывают режим видео, качество, состояние авторизации и настройки содержимого виджета.
- Разрешение потоков поддерживает авторизационные cookies, раздельные аудио- и видеодорожки и ограничение выбранного качества.

[0.1.1]: https://github.com/vornashev/OmaTube/releases/tag/v0.1.1

[0.1.0]: https://github.com/vornashev/OmaTube/releases/tag/v0.1.0
