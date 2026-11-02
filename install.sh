#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="vornashev.omatube"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
APP_ROOT="$HOME/.local/share/omatube"
APP_DIR="$APP_ROOT/app"
UNIT_DIR="$HOME/.config/systemd/user"
CONFIG_DIR="$HOME/.config/omatube"
RUNTIME_DIR="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}/omatube"
MARKER="$APP_ROOT/.installed-version"
BACKEND_ONLY=0

case "${1:-}" in
"") ;;
--backend-only) BACKEND_ONLY=1 ;;
*)
  echo "Usage: $0 [--backend-only]" >&2
  exit 2
  ;;
esac


for command in python node npm deno mpv ffmpeg ffprobe systemctl jq flock sha256sum; do
  if ! command -v "$command" >/dev/null; then
    echo "Missing dependency: $command" >&2
    echo "On Omarchy install prerequisites with: omarchy pkg add python nodejs npm deno mpv ffmpeg jq util-linux coreutils" >&2
    exit 1
  fi
done
VERSION="$(jq -er '.version' "$ROOT/manifest.json")"
EXTENSION_VERSION="$(jq -er '.version' "$ROOT/browser-extension/manifest.json")"
if [[ "$EXTENSION_VERSION" != "$VERSION" ]]; then
  echo "browser-extension/manifest.json version $EXTENSION_VERSION does not match plugin version $VERSION" >&2
  exit 1
fi


exec 9>"${XDG_RUNTIME_DIR}/omatube-install.lock"
flock 9
mkdir -p "$PLUGIN_DIR/backend" "$PLUGIN_DIR/catalog" "$PLUGIN_DIR/scripts" "$PLUGIN_DIR/bin" "$PLUGIN_DIR/systemd" "$APP_DIR/backend" "$APP_DIR/catalog" "$APP_DIR/scripts" "$APP_DIR/bin" "$APP_ROOT" "$CONFIG_DIR" "$RUNTIME_DIR" "$HOME/.local/bin" "$UNIT_DIR"
chmod 700 "$APP_ROOT" "$CONFIG_DIR" "$RUNTIME_DIR"
mkdir -p "$HOME/Videos/OmaTube"

if [[ "$(realpath "$ROOT")" != "$(realpath "$PLUGIN_DIR")" ]]; then
  for file in manifest.json bootstrap.sh install.sh uninstall.sh requirements.lock package.json package-lock.json PATCHES LICENSE; do
    install -C -m 644 "$ROOT/$file" "$PLUGIN_DIR/$file"
  done
  chmod 755 "$PLUGIN_DIR/bootstrap.sh" "$PLUGIN_DIR/install.sh" "$PLUGIN_DIR/uninstall.sh"
  # The UI lives in ui/; drop the pre-0.2 layout (QML, i18n.js and icons at the plugin root).
  rm -rf "$PLUGIN_DIR"/*.qml "$PLUGIN_DIR/i18n.js" "$PLUGIN_DIR/icons" "$PLUGIN_DIR/ui"
  cp -R "$ROOT/ui" "$PLUGIN_DIR/ui"
  for file in "$ROOT"/backend/*.py "$ROOT"/backend/*.lua; do install -m 644 "$file" "$PLUGIN_DIR/backend/$(basename "$file")"; done
  install -m 755 "$ROOT/catalog/worker.mjs" "$PLUGIN_DIR/catalog/worker.mjs"
  install -m 755 "$ROOT/scripts/patch-youtubei.mjs" "$PLUGIN_DIR/scripts/patch-youtubei.mjs"
  install -m 755 "$ROOT/scripts/build-firefox-extension.sh" "$PLUGIN_DIR/scripts/build-firefox-extension.sh"
  install -m 755 "$ROOT/bin/omatube" "$PLUGIN_DIR/bin/omatube"
  install -m 755 "$ROOT/bin/omatube-native-host" "$PLUGIN_DIR/bin/omatube-native-host"
  rm -rf "$PLUGIN_DIR/browser-extension"
  cp -R "$ROOT/browser-extension" "$PLUGIN_DIR/browser-extension"
  install -m 644 "$ROOT/systemd/omatube.service" "$PLUGIN_DIR/systemd/omatube.service"
fi

for file in "$ROOT"/backend/*.py "$ROOT"/backend/*.lua; do install -m 644 "$file" "$APP_DIR/backend/$(basename "$file")"; done
install -m 755 "$ROOT/catalog/worker.mjs" "$APP_DIR/catalog/worker.mjs"
install -m 755 "$ROOT/scripts/patch-youtubei.mjs" "$APP_DIR/scripts/patch-youtubei.mjs"
install -m 644 "$ROOT/requirements.lock" "$ROOT/package.json" "$ROOT/package-lock.json" "$APP_DIR/"
install -m 755 "$ROOT/bin/omatube" "$HOME/.local/bin/omatube"
install -m 755 "$ROOT/bin/omatube-native-host" "$APP_DIR/bin/omatube-native-host"
# Stable path for "Load unpacked" in Chromium; rebuilt so removed files do not linger.
rm -rf "$APP_ROOT/browser-extension"
cp -R "$ROOT/browser-extension" "$APP_ROOT/browser-extension"
find "$APP_ROOT/browser-extension" -name '*.test.mjs' -delete
# Firefox flavour: an unpacked folder for about:debugging and an .xpi for "Install Add-on From File".
"$ROOT/scripts/build-firefox-extension.sh" "$ROOT/browser-extension" "$APP_ROOT/browser-extension-firefox" "$APP_ROOT/omatube-firefox.xpi"
"$HOME/.local/bin/omatube" browser-setup >/dev/null || echo "Browser bridge was not installed; run: omatube browser-setup" >&2
install -m 644 "$ROOT/systemd/omatube.service" "$UNIT_DIR/omatube.service"

DEPENDENCY_DIGEST="$(sha256sum "$ROOT/requirements.lock" "$ROOT/package-lock.json" | sha256sum | cut -d' ' -f1)"
if [[ ! -x "$APP_DIR/.venv/bin/python" || ! -f "$APP_DIR/.dependency-digest" || "$(<"$APP_DIR/.dependency-digest")" != "$DEPENDENCY_DIGEST" ]]; then
  rm -rf "$APP_DIR/.venv" "$APP_DIR/node_modules"
  python -m venv "$APP_DIR/.venv"
  "$APP_DIR/.venv/bin/python" -m pip install --disable-pip-version-check --no-input --quiet --require-hashes --only-binary=:all: --no-deps -r "$APP_DIR/requirements.lock"
  npm ci --omit=dev --ignore-scripts --prefix "$APP_DIR"
  node "$APP_DIR/scripts/patch-youtubei.mjs"
  printf '%s\n' "$DEPENDENCY_DIGEST" > "$APP_DIR/.dependency-digest"
fi

systemctl --user daemon-reload
systemctl --user enable omatube.service >/dev/null
systemctl --user restart omatube.service
printf '%s\n' "$VERSION" > "$MARKER"
chmod 644 "$MARKER"

if ((BACKEND_ONLY)); then
  printf 'OmaTube backend %s installed.\n' "$VERSION"
  exit 0
fi

if command -v omarchy-shell >/dev/null && omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null
  omarchy plugin enable "$PLUGIN_ID" --after omarchy.clock
else
  echo "Omarchy Shell is not running. Enable after login: omarchy plugin enable $PLUGIN_ID --after omarchy.clock"
fi
printf 'OmaTube installed.\n'
