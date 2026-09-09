#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$HOME/.local/share/omatube"
APP="$APP_ROOT/app"
MARKER="$APP_ROOT/.installed-version"
UNIT="$HOME/.config/systemd/user/omatube.service"

if command -v jq >/dev/null; then
  VERSION="$(jq -er '.version' "$ROOT/manifest.json")"
  if [[ -r "$MARKER" && "$(<"$MARKER")" == "$VERSION" &&
        -x "$APP/.venv/bin/python" && -f "$APP/backend/main.py" &&
        -x "$HOME/.local/bin/omatube" && -f "$UNIT" ]]; then
    systemctl --user daemon-reload
    systemctl --user enable --now omatube.service >/dev/null
    printf 'OmaTube backend %s is ready.\n' "$VERSION"
    exit 0
  fi
fi

exec "$ROOT/install.sh" --backend-only
