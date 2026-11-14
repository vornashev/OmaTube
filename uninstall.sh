#!/bin/bash
set -euo pipefail
# System directories only: a binary planted earlier in the user's PATH must not run as part of setup.
export PATH=/usr/local/bin:/usr/bin

PLUGIN_ID="vornashev.omatube"
APP_ROOT="$HOME/.local/share/omatube"
LEGACY_UNIT_DIR="$HOME/.config/systemd/user"

if command -v omarchy >/dev/null; then omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true; fi
if [[ -x "$HOME/.local/bin/omatube" ]]; then "$HOME/.local/bin/omatube" stop >/dev/null 2>&1 || true; fi
if [[ -x "$HOME/.local/bin/omatube" ]]; then "$HOME/.local/bin/omatube" browser-setup --remove >/dev/null 2>&1 || true; fi
rm -f "$LEGACY_UNIT_DIR/omatube.service" "$LEGACY_UNIT_DIR/default.target.wants/omatube.service" "$HOME/.local/bin/omatube"
rm -rf "$APP_ROOT/app" "$APP_ROOT/browser-extension" "$APP_ROOT/browser-extension-firefox" "$APP_ROOT/omatube-firefox.xpi" "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$APP_ROOT" "$HOME/.config/omatube"
  echo "OmaTube and all local data removed."
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--purge]" >&2; exit 2
else
  echo "OmaTube removed; collection and preferences kept. Use --purge to delete them."
fi
