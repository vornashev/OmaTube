<!-- markdownlint-disable MD013 -->

# OmaTube

Native YouTube and YouTube Music player for [Omarchy](https://omarchy.org/). OmaTube runs as an Omarchy Shell bar widget with a local Python backend and mpv playback—no browser tab required.

[Русская версия](#русский)

## Features

- Search and browse YouTube and YouTube Music, including videos, tracks, playlists, channels, and artists.
- Audio, tiled-video, and floating-video playback through mpv.
- Queue controls, shuffle, repeat, seeking, volume, mute, and selectable video quality up to 2160p.
- Local saved media, bookmarks, play history, and editable playlists.
- Copy public YouTube playlists into the local collection.
- Optional authenticated YouTube session imported from Chromium cookies.
- Wide, compact and shelf panel formats with chapters, comments, synced lyrics and a playback options popover (speed, sleep timer, normalization).
- SponsorBlock segment skipping, local subscriptions with an RSS feed, and downloads to `~/Videos/OmaTube`.
- MPRIS integration for desktop media controls.
- “Watch in OmaTube” browser extension for Chromium-based browsers: moves the video from a YouTube tab to OmaTube at the same timestamp.
- Persistent playback state and configurable bar appearance.
- English and Russian interface; the language follows the system locale by default and can be switched in Settings → Language.

## Requirements

OmaTube targets Omarchy and requires:

- Omarchy Shell
- Python 3
- Node.js and npm
- Deno
- mpv
- FFmpeg (`ffmpeg` and `ffprobe`)
- `jq`, `flock`, and `sha256sum`

On Omarchy, install the system packages with:

```bash
omarchy pkg add python nodejs npm deno mpv ffmpeg jq util-linux coreutils
```

## Installation

Install and enable OmaTube with the standard Omarchy command:

```bash
omarchy plugin add https://github.com/vornashev/OmaTube.git --enable
```

No manual clone, directory change, or `sudo` is required. On first load, the
plugin automatically creates its Python environment, installs Node.js
dependencies, configures the `omatube` CLI and systemd user service, and starts
the backend.

The installer places files in
`~/.config/omarchy/plugins/vornashev.omatube` and application data in
`~/.local/share/omatube`.

To update later:

```bash
omarchy plugin update vornashev.omatube
```

## Usage

Use the bar widget to search, manage the queue and collection, and switch between audio, tiled video, and floating video. The helper CLI exposes backend state and requests:

```bash
omatube status
omatube details
omatube request '{"command":"play_url","url":"https://www.youtube.com/watch?v=VIDEO_ID"}'
```

Importing Chromium cookies is optional and is available in the widget settings. Cookies are filtered to YouTube domains and stored locally with owner-only permissions.

## Browser extension

The bundled extension adds a **Watch in OmaTube** button to YouTube, Shorts and YouTube Music. It pauses the video, puts it at the head of My queue in OmaTube and closes the tab; OmaTube starts it right away from the same moment, and whatever was playing moves to second place and later resumes where it stopped. The arrow next to the button offers **Play next** (right after the current video) and **Play last** (end of My queue). A keyboard shortcut (`Alt+Shift+O` by default) and a link context-menu item do the same. Hovering a video thumbnail anywhere on YouTube (feed, search, sidebar) shows a small OmaTube button in its corner. Clicking it puts the video at the end of My queue without leaving the page; right-click it for **Play now** or **Play next**.

Supported browsers: Chromium (the Omarchy default), Google Chrome, Brave, Vivaldi, Microsoft Edge, Opera, Thorium, Helium, Yandex Browser, Firefox 128+, Zen, LibreWolf, Floorp and Waterfox. Several browsers can be used at once: they share one OmaTube queue. Flatpak and Snap builds are listed as not supported, because their sandbox can't start the bridge.

1. The installer copies the extension to `~/.local/share/omatube/browser-extension` and registers the native messaging host for every browser it finds. OmaTube repeats this on every service start, so a browser installed later is picked up automatically; `omatube browser-setup` does it right away. For a browser that isn't in the list, run `omatube browser-setup --dir <its profile folder>` (add `--family gecko` for a Firefox fork); `--forget <folder>` removes it again.
2. Open `chrome://extensions`, enable **Developer mode**, click **Load unpacked** and pick `~/.local/share/omatube/browser-extension`.
3. After updating OmaTube, press **Reload** on the extension card.

Firefox: the installer also builds `~/.local/share/omatube/omatube-firefox.xpi` and registers the host for Firefox, Zen and LibreWolf (`~/.mozilla/native-messaging-hosts`, `~/.librewolf/native-messaging-hosts`). Release Firefox only installs signed add-ons, so either load `~/.local/share/omatube/browser-extension-firefox/manifest.json` from `about:debugging` → **This Firefox** → **Load Temporary Add-on** (until restart), or, in Firefox Developer Edition, Nightly or LibreWolf with `xpinstall.signatures.required` set to `false`, use **Install Add-on From File** in `about:addons`.

The extension talks to a small native host (`omatube-native-host`) over Chromium native messaging. No network port is opened. The host accepts only “status” and “transfer” messages, so the extension cannot run any other backend command. It starts `omatube.service` if the service is not running.

Settings:

- **Extension** (its options page): default action, close or keep the tab after a transfer, rewind 0–10 s, button placement (below the video, in the player bar, or both), Shorts, YouTube Music, the link menu item and the thumbnail button.
- **OmaTube** (Settings → Browser): accept videos from the browser, video mode for transferred videos, desktop notification, bridge status per browser, and reinstalling the bridge.

Settings → Browser shows one row per browser: connected (with time and extension version), reload the extension, not connected yet, bridge missing (with an Install button) or not supported. `omatube browser-status` prints the same as JSON, and `omatube browser-setup --remove` unregisters the host.

## Data and configuration

- Application runtime: `~/.local/share/omatube`
- Local library and playback state: `~/.local/share/omatube`
- Preferences and imported cookies: `~/.config/omatube`
- Plugin files: `~/.config/omarchy/plugins/vornashev.omatube`
- User service: `~/.config/systemd/user/omatube.service`

## Updating

Download or check out the new version and run `./install.sh` again. The installer replaces application files and dependencies while preserving local data and preferences.

## Uninstallation

```bash
./uninstall.sh
```

This preserves the local collection and preferences. Remove everything with:

```bash
./uninstall.sh --purge
```

## Development

Run the backend test suite from the repository root:

```bash
python -m unittest discover -s tests
node --test browser-extension/lib/
```

Release tags use the `vX.Y.Z` format. The release workflow verifies that the tag matches `manifest.json` and `package.json`, builds a source distribution, writes a SHA-256 checksum, and publishes both files to GitHub Releases.

## License

[MIT](LICENSE) © 2026 Artem Vornashev.

---

## Русский

Нативный проигрыватель YouTube и YouTube Music для [Omarchy](https://omarchy.org/). OmaTube работает как виджет панели Omarchy Shell, использует локальный Python-бэкенд и mpv и не требует открытой вкладки браузера.

[English version](#omatube)

### Возможности

- Поиск и просмотр YouTube и YouTube Music: видео, треки, плейлисты, каналы и исполнители.
- Воспроизведение аудио, видео в тайловом окне и плавающем окне через mpv.
- Очередь, перемешивание, повтор, перемотка, громкость, отключение звука и выбор качества видео до 2160p.
- Локально сохранённые медиа, закладки, история и редактируемые плейлисты.
- Копирование публичных плейлистов YouTube в локальную коллекцию.
- Необязательное подключение авторизованной сессии YouTube через импорт cookies из Chromium.
- Интеграция MPRIS для системного управления воспроизведением.
- Расширение «Смотреть в OmaTube» для Chromium-браузеров: переносит видео из вкладки YouTube в OmaTube с того же места.
- Сохранение состояния проигрывателя и настройка внешнего вида виджета панели.
- Интерфейс на английском и русском: язык по умолчанию берётся из системной локали, переключается в Настройки → Язык.

### Требования

OmaTube предназначен для Omarchy. Необходимы:

- Omarchy Shell
- Python 3
- Node.js и npm
- Deno
- mpv
- FFmpeg (`ffmpeg` и `ffprobe`)
- `jq`, `flock` и `sha256sum`

Установка системных пакетов в Omarchy:

```bash
omarchy pkg add python nodejs npm deno mpv ffmpeg jq util-linux coreutils
```

### Установка

Установите и сразу включите OmaTube стандартной командой Omarchy:

```bash
omarchy plugin add https://github.com/vornashev/OmaTube.git --enable
```

Ручной `git clone`, переход в каталог и `sudo` не нужны. При первой загрузке
плагин автоматически создаст Python-окружение, установит зависимости Node.js,
настроит CLI `omatube` и пользовательский сервис systemd, затем запустит
бэкенд.

Файлы плагина размещаются в
`~/.config/omarchy/plugins/vornashev.omatube`, данные приложения — в
`~/.local/share/omatube`.

Для последующего обновления:

```bash
omarchy plugin update vornashev.omatube
```

### Использование

Виджет панели позволяет искать контент, управлять очередью и коллекцией, а также переключаться между аудио, тайловым и плавающим видео. Вспомогательный CLI предоставляет состояние бэкенда и отправку команд:

```bash
omatube status
omatube details
omatube request '{"command":"play_url","url":"https://www.youtube.com/watch?v=VIDEO_ID"}'
```

Импорт cookies Chromium необязателен и доступен в настройках виджета. Cookies фильтруются по доменам YouTube и хранятся локально с доступом только для владельца.

### Расширение для браузера

Расширение из комплекта добавляет кнопку **«Смотреть в OmaTube»** на YouTube, в Shorts и в YouTube Music. Кнопка ставит видео на паузу, передаёт в OmaTube его ID и текущую позицию и закрывает вкладку. Видео встаёт первым в «Мою очередь» и сразу включается, а то, что играло, сдвигается на второе место и потом продолжится с того же момента. Стрелка рядом с кнопкой открывает варианты **«Следующим»** (сразу после текущего) и **«В конец очереди»**. То же самое делают горячая клавиша (по умолчанию `Alt+Shift+O`) и пункт в контекстном меню ссылок. При наведении на превью видео в любом месте YouTube (лента, поиск, боковая колонка) в его углу появляется маленькая кнопка OmaTube. Клик по ней добавляет видео в конец «Моей очереди», и вы остаётесь на странице. Правый клик открывает варианты **«Смотреть сейчас»** и **«Следующим»**.

Поддерживаемые браузеры: Chromium (браузер Omarchy по умолчанию), Google Chrome, Brave, Vivaldi, Microsoft Edge, Opera, Thorium, Helium, Яндекс Браузер, Firefox 128+, Zen, LibreWolf, Floorp и Waterfox. Можно пользоваться несколькими браузерами сразу: очередь OmaTube у них общая. Сборки Flatpak и Snap помечаются как неподдерживаемые: песочница не даёт запустить связку.

1. Установщик копирует расширение в `~/.local/share/omatube/browser-extension` и регистрирует native messaging host во всех найденных браузерах. OmaTube повторяет это при каждом запуске сервиса, поэтому браузер, установленный позже, подхватится сам; `omatube browser-setup` сделает это сразу. Для браузера, которого нет в списке, выполните `omatube browser-setup --dir <папка его профиля>` (для форка Firefox добавьте `--family gecko`); `--forget <папка>` убирает его.
2. Откройте `chrome://extensions`, включите **«Режим разработчика»**, нажмите **«Загрузить распакованное»** и выберите `~/.local/share/omatube/browser-extension`.
3. После обновления OmaTube нажмите **«Обновить»** на карточке расширения.

Firefox: установщик также собирает `~/.local/share/omatube/omatube-firefox.xpi` и регистрирует host для Firefox, Zen и LibreWolf (`~/.mozilla/native-messaging-hosts`, `~/.librewolf/native-messaging-hosts`). Обычный Firefox ставит только подписанные дополнения, поэтому либо загрузите `~/.local/share/omatube/browser-extension-firefox/manifest.json` через `about:debugging` → **«Этот Firefox»** → **«Загрузить временное дополнение»** (до перезапуска), либо в Firefox Developer Edition, Nightly или LibreWolf с `xpinstall.signatures.required` = `false` выберите **«Установить дополнение из файла»** в `about:addons`.

Расширение общается с небольшим native host (`omatube-native-host`) через native messaging Chromium. Сетевой порт не открывается. Host принимает только сообщения «статус» и «перенос», поэтому расширение не может выполнить другие команды бэкенда. Если `omatube.service` не запущен, host запускает его.

Настройки:

- **В расширении** (страница параметров): действие по умолчанию, закрывать или оставлять вкладку после переноса, откат на 0–10 с, место кнопки (под видео, в панели плеера или в обоих местах), Shorts, YouTube Music, пункт в меню ссылок и кнопка на превью.
- **В OmaTube** (Настройки → Браузер): приём видео из браузера, режим видео для перенесённых роликов, уведомление, статус связки по браузерам и её переустановка.

В «Настройки → Браузер» у каждого браузера своя строка: подключено (с временем и версией расширения), нужно перезагрузить расширение, ещё не подключалось, нет связки (с кнопкой «Установить») или не поддерживается. `omatube browser-status` выводит то же в JSON, а `omatube browser-setup --remove` удаляет регистрацию host.

### Данные и настройки

- Файлы приложения: `~/.local/share/omatube`
- Локальная медиатека и состояние проигрывателя: `~/.local/share/omatube`
- Настройки и импортированные cookies: `~/.config/omatube`
- Файлы плагина: `~/.config/omarchy/plugins/vornashev.omatube`
- Пользовательский сервис: `~/.config/systemd/user/omatube.service`

### Обновление

Скачайте или получите новую версию и снова запустите `./install.sh`. Установщик заменит файлы приложения и зависимости, сохранив локальные данные и настройки.

### Удаление

```bash
./uninstall.sh
```

По умолчанию локальная коллекция и настройки сохраняются. Полное удаление:

```bash
./uninstall.sh --purge
```

### Разработка

Запуск тестов бэкенда из корня репозитория:

```bash
python -m unittest discover -s tests
node --test browser-extension/lib/
```

Релизные теги имеют формат `vX.Y.Z`. Релизный workflow проверяет соответствие тега версиям в `manifest.json` и `package.json`, собирает архив исходного кода, создаёт контрольную сумму SHA-256 и публикует оба файла в GitHub Releases.

### Лицензия

[MIT](LICENSE) © 2026 Artem Vornashev.
