#!/usr/bin/env bash
# Repository consistency checks shared by CI and scripts/release.sh.
#   scripts/check.sh            versions agree, manifest is loadable, CHANGELOG is well-formed
#   scripts/check.sh --tag vX.Y.Z   also require that the tag matches the version and has a CHANGELOG section
set -euo pipefail
cd "$(dirname "$0")/.."

tag=""
case "${1:-}" in
"") ;;
--tag) tag="${2:?--tag needs a value}" ;;
-h | --help) sed -n '2,4p' "$0"; exit 0 ;;
*) echo "unknown option: $1" >&2; exit 2 ;;
esac

failed=0
fail() { echo "check: $*" >&2; failed=1; }

# One version everywhere: the plugin, npm metadata and the browser extension.
version="$(jq -er .version manifest.json)"
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "manifest.json version '$version' is not X.Y.Z"
for source in "package.json:.version" "package-lock.json:.version" 'package-lock.json:.packages[""].version' "browser-extension/src/manifest.json:.version"; do
  file="${source%%:*}"; query="${source#*:}"
  other="$(jq -er "$query" "$file")"
  [[ $other == "$version" ]] || fail "$file $query is $other, manifest.json says $version"
done

if [[ -n $tag ]]; then
  [[ $tag == "v$version" ]] || fail "tag $tag does not match manifest.json version $version"
  scripts/changelog-section.sh "$version" >/dev/null || fail "CHANGELOG.md has no section for $version"
fi

# The checks omarchy-plugin-validate runs on install, so a broken manifest never reaches users.
jq -e '.schemaVersion == 1 and (.id | test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) and (.kinds | length > 0)' manifest.json >/dev/null \
  || fail "manifest.json: bad schemaVersion, id or kinds"
while IFS= read -r entry; do
  [[ $entry != /* && $entry != *..* && -f $entry ]] || fail "manifest.json entry point '$entry' is missing or unsafe"
done < <(jq -r '.entryPoints[]' manifest.json)
link="$(find . -name .git -prune -o -name node_modules -prune -o -name .venv -prune -o -type l -print -quit)"
[[ -z $link ]] || fail "symlinks are not allowed in a plugin: $link"
# The marketplace reads manifest.json at the root and one level down, and accepts exactly one.
manifests="$(git ls-files | grep -E '^([^/]+/)?manifest\.json$' || true)"
[[ $manifests == manifest.json ]] || fail "only the root manifest.json may sit within one level of the root; found: ${manifests//$'\n'/, }"

# Every icon the UI asks for by a literal name exists.
while IFS= read -r name; do
  [[ -f ui/icons/$name.svg ]] || fail "ui/icons/$name.svg is referenced but missing"
done < <(grep -ohE '\b(name|icon): *"[a-z0-9-]+"' ui/*.qml | sed -E 's/.*"(.*)"/\1/' | sort -u)

# CHANGELOG keeps an Unreleased section on top and a link for every version heading.
grep -q '^## \[Unreleased\]' CHANGELOG.md || fail "CHANGELOG.md has no '## [Unreleased]' section"
while IFS= read -r heading; do
  grep -q "^\[$heading\]: " CHANGELOG.md || fail "CHANGELOG.md has no link for [$heading]"
done < <(sed -nE 's/^## \[([^]]+)\].*/\1/p' CHANGELOG.md)

if command -v shellcheck >/dev/null; then
  shellcheck -S warning install.sh bootstrap.sh uninstall.sh scripts/*.sh || fail "shellcheck reported problems"
fi

((failed == 0)) && echo "check: ok ($version)"
exit "$failed"
