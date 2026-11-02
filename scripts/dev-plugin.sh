#!/usr/bin/env bash
# Copy the shell UI (ui/ and the manifest) into the installed plugin directory.
# omarchy-shell reloads plugin code when files there change. Run with --watch to keep syncing.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
dest="$HOME/.config/omarchy/plugins/vornashev.omatube"

sync() {
  mkdir -p "$dest/ui"
  # Pre-0.2 installs kept the UI at the plugin root.
  rm -rf "$dest"/*.qml "$dest/i18n.js" "$dest/icons"
  rsync -a --delete "$repo/ui/" "$dest/ui/"
  rsync -a "$repo/manifest.json" "$dest/"
}

case "${1:-}" in
"" | --watch) ;;
-h | --help) sed -n '2,3p' "$0"; exit 0 ;;
*) echo "unknown option: $1" >&2; exit 2 ;;
esac

sync
echo "synced to $dest"
if [[ "${1:-}" == "--watch" ]]; then
  while inotifywait -qq -r -e close_write,create,delete,move "$repo/ui" "$repo/manifest.json"; do
    sync
    echo "synced $(date +%T)"
  done
fi
