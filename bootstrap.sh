#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/.local/share/omatube/app"
if [[ ! -x "$APP/.venv/bin/python" || ! -f "$APP/backend/main.py" ]]; then
  echo "OmaTube backend is not installed. Run: cd '$HOME/Projects/OmaTube' && ./install.sh" >&2
  exit 1
fi
systemctl --user daemon-reload
systemctl --user enable --now omatube.service >/dev/null
printf 'OmaTube backend is ready.\n'
