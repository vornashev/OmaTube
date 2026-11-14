#!/usr/bin/env bash
# Run the current working tree: install and restart the backend,
# copy the plugin UI and restart omarchy-shell so everything shows up at once.
#   --plugin-only   skip the backend; only copy the UI and restart the shell
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
if [[ -t 1 ]]; then
  say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
else
  say() { printf '==> %s\n' "$*"; }
fi

plugin_only=0
for arg in "$@"; do
  case "$arg" in
  --plugin-only) plugin_only=1 ;;
  -h | --help) sed -n '2,4p' "$0"; exit 0 ;;
  *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ $plugin_only == 0 ]]; then
  say "installing the backend"
  "$repo/install.sh" --backend-only
  "$HOME/.local/bin/omatube" status >/dev/null \
    || echo "backend not running: omatube logs" >&2
fi

say "copying the plugin"
"$repo/scripts/dev-plugin.sh"

say "restarting omarchy-shell"
omarchy-restart-shell

say "done"
