#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="vornashev.omatube"
APP_ROOT="$HOME/.local/share/omatube"
UNIT="$HOME/.config/systemd/user/omatube.service"

if command -v omarchy >/dev/null; then omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true; fi
systemctl --user disable --now omatube.service >/dev/null 2>&1 || true
rm -f "$UNIT" "$HOME/.local/bin/omatube"
rm -rf "$APP_ROOT/app" "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
systemctl --user daemon-reload
if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$APP_ROOT" "$HOME/.config/omatube"
  echo "OmaTube and all local data removed."
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--purge]" >&2; exit 2
else
  echo "OmaTube removed; collection and preferences kept. Use --purge to delete them."
fi
