<!-- markdownlint-disable MD013 -->

# Development

## Layout

| Path | What it is |
| --- | --- |
| `manifest.json` | Omarchy plugin manifest; the entry point is `ui/BarWidget.qml` |
| `ui/` | Omarchy Shell UI: QML components, `i18n.js` (Russian source strings → English) and Lucide icons |
| `backend/` | Python service: player state, mpv control, storage (SQLite), MPRIS, SponsorBlock, lyrics, downloads, image cache |
| `catalog/worker.mjs` | Node.js worker on top of youtubei.js for search, channels, playlists and comments |
| `bin/omatube` | CLI and browser bridge setup |
| `bin/omatube-native-host` | Native messaging host for the browser extension |
| `browser-extension/` | “Watch in OmaTube” extension (Chromium MV3; the Firefox build is generated) |
| `systemd/omatube.service` | Hardened user service that runs the backend |
| `install.sh`, `bootstrap.sh`, `uninstall.sh` | Installer, first-load hook used by the widget, uninstaller |
| `scripts/` | Dev sync, release tooling, checks, the youtubei.js patch and the Firefox build |
| `tests/` | Backend and native-host tests (`unittest`) |

At runtime the plugin lives in `~/.config/omarchy/plugins/vornashev.omatube`, and the backend is installed into `~/.local/share/omatube/app`. The UI talks to the backend over a Unix socket at `$XDG_RUNTIME_DIR/omatube/backend.sock`.

## Set up

```bash
git clone https://github.com/vornashev/OmaTube.git && cd OmaTube
python -m venv .venv
.venv/bin/pip install --require-hashes --only-binary=:all: --no-deps -r requirements.lock
npm ci --ignore-scripts && node scripts/patch-youtubei.mjs
```

## Run your working tree

```bash
scripts/dev-reload.sh                # install the backend, restart omatube.service, copy the UI, restart the shell
scripts/dev-reload.sh --plugin-only  # UI only
scripts/dev-plugin.sh --watch        # copy ui/ on every save; Omarchy Shell reloads changed plugin files
```

To see QML warnings and backend logs:

```bash
journalctl --user -f -t omarchy-shell | grep omatube
journalctl --user -fu omatube
```

## Test

```bash
.venv/bin/python -m unittest discover -s tests
node --test 'browser-extension/lib/*.test.mjs'
scripts/check.sh   # versions, manifest, icons, CHANGELOG format, shellcheck when installed
```

CI runs the same steps on every push to `main` and on every pull request.

When Qt 6 Quick Test (`qmltestrunner`) is installed, the Python suite also runs headless QML checks at 100% and 200% display scale: hidden animations, first-use panel/page loading, retained scroll state, navigation and cover decoding. Shell services and page bodies are replaced by test fixtures; no running shell or backend is contacted.

QML checks also cover idle view eviction and lists of 1,000 items. When Quickshell is available, a separate native socket test starts an isolated instance with a temporary backend socket; it does not load the desktop shell. Cache tests include Node.js unit tests from `catalog/cache.test.mjs`.

The widget subscribes to `backend.sock` with a newline-delimited JSON request: `{"command":"subscribe","details":false}`. The first `state` event has `reset:true`; later events contain only changed fields in `result`. Sending another subscription request changes the detail level or retained operation IDs; `full:true` requests a new snapshot. Playback updates are coalesced to at most four events per second, and an unchanged idle state sends no frames. Existing one-request CLI connections keep their previous behavior.

## Translations

UI strings are written in Russian in QML (`L.tr("…")`), and `ui/i18n.js` maps them to English. When you add a string, add its English translation to `ui/i18n.js`. Backend messages live in `backend/i18n.py`.

## Changelog

Every user-visible change gets a line under `## [Unreleased]` in [CHANGELOG.md](../CHANGELOG.md), in the matching group: `Added`, `Changed`, `Fixed` or `Removed` (and `Deprecated` or `Security` when needed). Write it for users: what changed and how it affects them, not which file was touched.

## Releasing

Versions follow [Semantic Versioning](https://semver.org/). While OmaTube is 0.x, a minor bump (0.2 → 0.3) means new features or breaking changes, and a patch bump (0.2.0 → 0.2.1) means fixes only, including a bumped `yt-dlp` when YouTube breaks playback.

1. Make sure `main` is clean and `[Unreleased]` describes the release.
2. Run `scripts/release.sh X.Y.Z`. It:
   - sets the version in `manifest.json`, `package.json`, `package-lock.json` and `browser-extension/manifest.json`;
   - renames `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`, opens a new empty `[Unreleased]` and updates the compare links;
   - runs `scripts/check.sh` and the tests;
   - commits `Release vX.Y.Z` and creates an annotated tag `vX.Y.Z` whose message is the changelog section.
3. Review with `git show vX.Y.Z`, then publish with `git push --atomic origin main vX.Y.Z`.

Pushing the tag starts `.github/workflows/release.yml`. The workflow checks the tag against the versions and the changelog, then creates a GitHub release with notes taken from CHANGELOG.md. The release attaches:

- a source archive;
- the Firefox `.xpi`;
- `SHA256SUMS`.

`omarchy plugin update` pulls `main` with `git merge --ff-only`. Never rewrite published history on `main`, or installed copies stop updating.

## Updating dependencies

- **yt-dlp and other Python packages:** edit `requirements.txt`, then regenerate `requirements.lock` with hashes for the wheels Omarchy uses (CPython on x86_64 Linux). The installer reinstalls dependencies when the lock files change.
- **youtubei.js:** bump it in `package.json`, run `npm install --ignore-scripts`, then run `node scripts/patch-youtubei.mjs`. The patch fails loudly if upstream code changed; see [PATCHES](../PATCHES).
