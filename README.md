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
- MPRIS integration for desktop media controls.
- Persistent playback state and configurable bar appearance.

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

### Release archive

Download `omatube-vX.Y.Z.tar.gz` and its checksum from the corresponding GitHub release, then run:

```bash
tar -xzf omatube-vX.Y.Z.tar.gz
cd omatube-vX.Y.Z
./install.sh
```

### Source checkout

```bash
git clone https://github.com/vornashev/OmaTube.git
cd OmaTube
./install.sh
```

The installer copies the widget to `~/.config/omarchy/plugins/vornashev.omatube`, creates the backend environment under `~/.local/share/omatube`, installs the `omatube` command, and enables the user service.

If Omarchy Shell is not running during installation, enable the widget after login:

```bash
omarchy plugin enable vornashev.omatube --after omarchy.clock
```

## Usage

Use the bar widget to search, manage the queue and collection, and switch between audio, tiled video, and floating video. The helper CLI exposes backend state and requests:

```bash
omatube status
omatube details
omatube request '{"command":"play_url","url":"https://www.youtube.com/watch?v=VIDEO_ID"}'
```

Importing Chromium cookies is optional and is available in the widget settings. Cookies are filtered to YouTube domains and stored locally with owner-only permissions.

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
- Сохранение состояния проигрывателя и настройка внешнего вида виджета панели.

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

#### Архив релиза

Скачайте `omatube-vX.Y.Z.tar.gz` и файл контрольной суммы из соответствующего GitHub Release, затем выполните:

```bash
tar -xzf omatube-vX.Y.Z.tar.gz
cd omatube-vX.Y.Z
./install.sh
```

#### Исходный код

```bash
git clone https://github.com/vornashev/OmaTube.git
cd OmaTube
./install.sh
```

Установщик копирует виджет в `~/.config/omarchy/plugins/vornashev.omatube`, создаёт окружение бэкенда в `~/.local/share/omatube`, устанавливает команду `omatube` и включает пользовательский сервис.

Если Omarchy Shell не был запущен во время установки, включите виджет после входа в систему:

```bash
omarchy plugin enable vornashev.omatube --after omarchy.clock
```

### Использование

Виджет панели позволяет искать контент, управлять очередью и коллекцией, а также переключаться между аудио, тайловым и плавающим видео. Вспомогательный CLI предоставляет состояние бэкенда и отправку команд:

```bash
omatube status
omatube details
omatube request '{"command":"play_url","url":"https://www.youtube.com/watch?v=VIDEO_ID"}'
```

Импорт cookies Chromium необязателен и доступен в настройках виджета. Cookies фильтруются по доменам YouTube и хранятся локально с доступом только для владельца.

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
```

Релизные теги имеют формат `vX.Y.Z`. Релизный workflow проверяет соответствие тега версиям в `manifest.json` и `package.json`, собирает архив исходного кода, создаёт контрольную сумму SHA-256 и публикует оба файла в GitHub Releases.

### Лицензия

[MIT](LICENSE) © 2026 Artem Vornashev.
