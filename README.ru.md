<!-- markdownlint-disable MD013 MD033 -->

# OmaTube

[![Release](https://img.shields.io/github/v/release/vornashev/OmaTube)](https://github.com/vornashev/OmaTube/releases/latest)
[![CI](https://github.com/vornashev/OmaTube/actions/workflows/ci.yml/badge.svg)](https://github.com/vornashev/OmaTube/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

YouTube и YouTube Music прямо в панели [Omarchy](https://omarchy.org/). OmaTube — это виджет Omarchy Shell с локальным Python-бэкендом и mpv. Он ищет, ставит в очередь и воспроизводит аудио и видео без открытой вкладки браузера.

[English](README.md) · **Русский**

<!--
  Скриншоты: положите файлы в docs/screenshots/ и раскомментируйте.
  <p align="center"><img src="docs/screenshots/wide.png" alt="Широкая панель OmaTube" width="860"></p>
-->

## Возможности

- **Поиск и просмотр** YouTube и YouTube Music: видео, треки, плейлисты, альбомы, каналы и исполнители.
- **Аудио, видео в тайле или в плавающем окне** через mpv: качество до 2160p, скорость, таймер сна, нормализация громкости.
- **Две очереди.** Отдельные видео попадают в «Мою очередь». Плейлисты, альбомы и радио играют в «Сейчас играет». Прерванный плейлист продолжается с того же трека и секунды.
- **Медиатека:** сохранённые видео, редактируемые плейлисты, копии публичных плейлистов, история, статистика прослушивания и сохранённые сессии очереди.
- **Подписки без аккаунта:** RSS-лента выбранных каналов или импорт подписок из аккаунта.
- **SponsorBlock**, главы, синхронизированный текст песен (LRCLIB), комментарии и превью кадров на таймлайне.
- **Загрузки** аудио (Opus) или видео (MP4) в `~/Videos/OmaTube`.
- **Расширение «Смотреть в OmaTube»** для Chromium, Chrome, Brave, Vivaldi, Edge, Opera, Firefox, Zen, LibreWolf и других браузеров. Оно переносит видео из вкладки YouTube в OmaTube с того же момента.
- **Широкий, компактный и полочный форматы** панели, настраиваемый виджет в баре и управление через MPRIS.
- **Русский и английский** интерфейс; язык берётся из системной локали.

## Требования

Omarchy с Omarchy Shell и пакеты:

```bash
omarchy pkg add python nodejs npm deno mpv ffmpeg jq util-linux coreutils
```

## Установка

```bash
omarchy plugin add https://github.com/vornashev/OmaTube.git --enable
```

При первой загрузке плагин создаст Python-окружение, установит зависимости Node.js, настроит команду `omatube` и пользовательский сервис systemd, затем запустит бэкенд. `sudo` не нужен. Первый запуск занимает около минуты, пока скачиваются зависимости.

Затем откройте виджет в панели. Экран приветствия предложит подключить аккаунт YouTube. Это необязательно, подключение импортирует cookies из Chromium.

### Обновление

```bash
omarchy plugin update vornashev.omatube
```

Медиатека и настройки сохраняются. Если пользуетесь расширением, после обновления нажмите **«Обновить»** на его карточке в `chrome://extensions`. Список изменений — в [CHANGELOG.md](CHANGELOG.md) (на английском).

### Удаление

```bash
~/.config/omarchy/plugins/vornashev.omatube/uninstall.sh          # медиатека и настройки сохранятся
~/.config/omarchy/plugins/vornashev.omatube/uninstall.sh --purge  # удалить всё
```

Используйте этот скрипт, а не `omarchy plugin remove`: он ещё и останавливает сервис бэкенда и снимает регистрацию моста для браузера.

## Как пользоваться

Нажмите на виджет, чтобы открыть панель. Play на отдельном видео ставит его первым в **«Мою очередь»** и сразу включает. То, что играло, сдвигается на второе место и потом продолжится с того же момента. Плейлист, альбом, радио или «Играть всё» заполняют **«Сейчас играет»**. Когда «Моя очередь» заканчивается, плейлист на паузе продолжается с того же трека и секунды.

Команда `omatube` обращается к бэкенду:

```bash
omatube status                     # состояние воспроизведения в JSON
omatube details                    # полное состояние: очередь, медиатека, настройки
omatube request '{"command":"play_url","url":"https://youtu.be/VIDEO_ID"}'
omatube browser-status             # состояние моста по браузерам
omatube browser-setup              # заново зарегистрировать мост
```

## Расширение для браузера

Расширение из комплекта добавляет кнопку **«Смотреть в OmaTube»** на YouTube, в Shorts и в YouTube Music. Ещё оно добавляет кнопку при наведении на превью, горячую клавишу `Alt+Shift+O` и пункт в контекстном меню ссылок. Видео, которые уже стоят в очереди OmaTube, отмечаются на превью YouTube.

Быстрый старт в браузерах на Chromium: откройте `chrome://extensions`, включите **«Режим разработчика»**, нажмите **«Загрузить распакованное»** и выберите `~/.local/share/omatube/browser-extension`.

**Firefox, Zen, LibreWolf.** Обычный Firefox ставит только подписанные дополнения. Поэтому либо загрузите `~/.local/share/omatube/browser-extension-firefox/manifest.json` через `about:debugging` → «Этот Firefox» → «Загрузить временное дополнение» (до перезапуска браузера), либо в Developer Edition, Nightly или LibreWolf с `xpinstall.signatures.required = false` установите `~/.local/share/omatube/omatube-firefox.xpi` через `about:addons`.

**Другие браузеры.** Если браузера нет в списке, выполните `omatube browser-setup --dir <папка профиля>`; для форков Firefox добавьте `--family gecko`. Сборки Flatpak и Snap не поддерживаются: песочница не даёт запустить мост.

Подробности о настройках и устройстве моста — в [docs/browser-extension.md](docs/browser-extension.md) (на английском).

## Приватность

У OmaTube нет телеметрии и собственного аккаунта. Всё хранится на вашем компьютере:

- **Медиатека, история и состояние плеера:** `~/.local/share/omatube` (SQLite)
- **Настройки и импортированные cookies:** `~/.config/omatube` (права `0600`). Cookies фильтруются по доменам YouTube.
- **Кэш превью:** `~/.local/share/omatube/cache/images` (до 256 МБ)

Сетевые запросы уходят только в YouTube (`youtube.com`, `i.ytimg.com`, `yt3.ggpht.com`), SponsorBlock (`sponsor.ajay.app`) и LRCLIB (`lrclib.net`). Бэкенд слушает Unix-сокет и локальный кэш картинок на `127.0.0.1:47865`; кэш отдаёт превью только с разрешённых хостов. Расширение работает через native messaging и не открывает портов.

## Если что-то не работает

| Симптом | Что сделать |
| --- | --- |
| Виджет пишет, что бэкенд недоступен | `systemctl --user status omatube` и `journalctl --user -u omatube -n 50` |
| Перестали играть видео или сломался поиск | YouTube что-то поменял; обновитесь через `omarchy plugin update vornashev.omatube` и проверьте, нет ли нового релиза |
| Не открывается видео 18+ или для спонсоров | Подключите аккаунт в Настройки → Аккаунт (импорт cookies из Chromium) |
| Расширение пишет «не подключено» | `omatube browser-status`, затем `omatube browser-setup` и перезагрузите расширение |
| Другое | [Создайте issue](https://github.com/vornashev/OmaTube/issues/new/choose) с выводом `omatube status` |

## Участие в разработке

Баг-репорты и pull request'ы приветствуются. Как поднять окружение, запустить тесты и выпустить релиз — в [CONTRIBUTING.md](CONTRIBUTING.md) и [docs/development.md](docs/development.md).

## Отказ от ответственности

OmaTube — независимый проект. Он не связан с Google или YouTube и не одобрен ими. YouTube — товарный знак Google LLC. Используйте OmaTube в соответствии с Условиями использования YouTube.

## Лицензия

[MIT](LICENSE) © 2026 Artem Vornashev
