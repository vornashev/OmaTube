#!/bin/bash
# Builds the Firefox flavour of browser-extension/src/: the same code with a Gecko manifest.
# Usage: build-firefox-extension.sh <source dir> <output dir> [<output .xpi>]
set -euo pipefail
# System directories only: a binary planted earlier in the user's PATH must not run as part of setup.
export PATH=/usr/local/bin:/usr/bin

SOURCE="$1"
OUT="$2"
XPI="${3:-}"

rm -rf "$OUT"
cp -R "$SOURCE" "$OUT"
find "$OUT" -name '*.test.mjs' -delete

# Firefox runs MV3 backgrounds as event pages (no service worker), wants a fixed add-on id for
# native messaging and ignores the Chromium-only key / minimum version.
jq '
  del(.key, .minimum_chrome_version, .options_page)
  | .background = {scripts: ["lib/time.js", "background.js"]}
  | .options_ui = {page: "options.html", open_in_tab: true}
  | .browser_specific_settings = {gecko: {
      id: "omatube@vornashev",
      strict_min_version: "128.0",
      data_collection_permissions: {required: ["none"]}
    }}
' "$SOURCE/manifest.json" > "$OUT/manifest.json"

if [[ -n "$XPI" ]]; then
  rm -f "$XPI"
  python - "$OUT" "$XPI" <<'PY'
import sys, zipfile
from pathlib import Path
root, target = Path(sys.argv[1]), sys.argv[2]
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob("*")):
        if path.is_file(): archive.write(path, path.relative_to(root).as_posix())
PY
fi
