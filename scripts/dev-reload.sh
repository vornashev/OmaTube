#!/usr/bin/env bash
# Run the current working tree: install the backend and restart omatube.service,
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
  for _ in {1..20}; do
    systemctl --user is-active --quiet omatube.service && break
    sleep 0.25
  done
  systemctl --user is-active --quiet omatube.service \
    || echo "backend not running: journalctl --user -u omatube -n 30" >&2
fi

say "copying the plugin"
"$repo/scripts/dev-plugin.sh"

say "restarting omarchy-shell"
omarchy-restart-shell

say "done"
