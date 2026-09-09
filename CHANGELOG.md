<!-- markdownlint-disable MD013 MD024 -->

# Changelog

All notable changes to OmaTube are documented in this file. Versions follow [Semantic Versioning](https://semver.org/), and release dates use `YYYY-MM-DD`.

[Русская версия](#русский)

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

[0.1.0]: https://github.com/vornashev/OmaTube/releases/tag/v0.1.0
