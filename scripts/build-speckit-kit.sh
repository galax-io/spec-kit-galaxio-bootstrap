#!/usr/bin/env bash
#
# build-speckit-kit.sh — regenerate the Spec Kit kit that template/ carries.
#
# The kit is what every repository of the organization gets, byte for byte: the
# skills of Claude Code (.claude/skills) and Codex (.agents/skills), and the
# Spec Kit files they run on (.specify/scripts, templates, extensions, presets,
# workflows, extensions.yml). It is generated here, once, by the pinned Spec Kit
# CLI through setup-speckit.sh, and then reaches repositories by `copier update`
# or `scripts/adopt.sh --speckit`. Nothing runs `specify` in a repository, so
# no two repositories can hold different skills.
#
# Left out because they differ on every run (time stamps, hashes of the files
# written, Python's __pycache__) or belong to one checkout: the registries and integration manifests
# of the CLI, the extension cache and backups, feature.json. Whatever of that a
# repository holds is removed by adopt.sh --speckit and ignored by git.
#
# .specify/speckit-kit.sha256 lists the hash of every file of the kit, so that
# scripts/check-speckit.sh can tell a repository's kit from the template's.
# .specify/memory/ (the constitution) is the repository's own and is not listed;
# the template carries its starting point, which copier and adopt.sh never replace.
#
# Usage:
#   scripts/build-speckit-kit.sh           # rewrite the kit in template/
#   scripts/build-speckit-kit.sh --check   # fail when template/ is not what the CLI generates
#
# Needs the `specify` CLI at exactly KIT_VERSION, network access (extensions
# and the preset install from GitHub) and git.
# Env: SPECKIT_DEEP_MODEL / SPECKIT_LIGHT_MODEL, as for setup-speckit.sh.

set -euo pipefail

# The one place the version of Spec Kit is chosen for the whole organization.
KIT_VERSION=1.2.2

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
template="${TEMPLATE_DIR:-$root/template}"
MANIFEST=".specify/speckit-kit.sha256"
# What the manifest does not list: the repository's own constitution and its marker.
OWN=".specify/memory/"

mode=write
case "${1:-}" in
  "")      ;;
  --check) mode=check ;;
  --help|-h) sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
esac

command -v specify >/dev/null 2>&1 || { echo "error: 'specify' not found on PATH (uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git@v$KIT_VERSION)" >&2; exit 2; }
have="$(specify version 2>/dev/null | sed -n 's/.*CLI Version[^0-9]*\([0-9][0-9.]*\).*/\1/p')"
[ "$have" = "$KIT_VERSION" ] || { echo "error: the kit is built by Spec Kit $KIT_VERSION, found ${have:-unknown}" >&2; exit 2; }

if command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum "$@"; }; else sha256() { shasum -a 256 "$@"; }; fi

work="$(mktemp -d)"; stage="$(mktemp -d)"; log="$(mktemp)"
trap 'rm -rf "$work" "$stage" "$log"' EXIT

# 1. Install into an empty project; setup-speckit.sh writes its log next to itself.
cp "$root/setup-speckit.sh" "$work/"
if ! ( cd "$work" && git init -q && bash setup-speckit.sh ) >"$log" 2>&1; then
  tail -40 "$log" >&2
  echo "error: setup-speckit.sh failed" >&2
  exit 1
fi
rm -f "$work/setup-speckit.sh" "$work/speckit-install.log"

# 2. The files of the kit.
list="$work/.kit-files"
( cd "$work" && find .claude/skills .agents/skills .specify -type f \
    ! -path '*/__pycache__/*' ! -name '*.pyc' \
    ! -path '.specify/extensions/.registry' \
    ! -path '.specify/extensions/.cache/*' \
    ! -path '.specify/extensions/.backup/*' \
    ! -path '.specify/presets/.registry' \
    ! -path '.specify/integrations/*.manifest.json' \
    ! -path '.specify/workflows/workflow-registry.json' \
    ! -path '.specify/feature.json' \
  | LC_ALL=C sort ) > "$list"
tar -cf - -C "$work" -T "$list" | tar -xf - -C "$stage"

# 3. The manifest: every file but the repository's own.
( cd "$stage" && grep -vF "$OWN" "$list" | while IFS= read -r f; do sha256 "$f"; done ) > "$stage/$MANIFEST"

# 4. Write, or compare.
kit_dirs=(.claude/skills .agents/skills .specify)
if [ "$mode" = check ]; then
  rc=0
  for d in "${kit_dirs[@]}"; do
    diff -rq "$stage/$d" "$template/$d" >"$log" 2>&1 || { rc=1; head -20 "$log" >&2; }
  done
  [ "$rc" = 0 ] && echo "template/ holds the kit Spec Kit $KIT_VERSION generates" \
    || echo "error: template/ is not the kit Spec Kit $KIT_VERSION generates; run scripts/build-speckit-kit.sh" >&2
  exit "$rc"
fi

for d in "${kit_dirs[@]}"; do rm -rf "${template:?}/$d"; done
mkdir -p "$template"
tar -cf - -C "$stage" "${kit_dirs[@]}" | tar -xf - -C "$template"
echo "kit: $(grep -c . "$template/$MANIFEST") files in $template (Spec Kit $KIT_VERSION)"
