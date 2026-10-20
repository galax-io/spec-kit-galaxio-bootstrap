#!/usr/bin/env bash
#
# build-speckit-layer.sh — regenerate the layer of a preset: the `specify` skills with the preset's text.
#
# A layer is what one repository gets on top of the organization's kit (template/): the two skill files
# of a command that a preset wraps, for Claude Code (.claude/skills) and Codex (.agents/skills), and
# .specify/speckit-overlay.sha256 with their hashes. It is generated here, by the pinned Spec Kit CLI,
# from presets/<name>/, and reaches a repository only by `scripts/adopt.sh --speckit --overlay <name>`.
# Nothing runs `specify` in that repository, and template/ is not touched.
#
# The CLI installs a preset's skill for the default integration only, rewrites the skill's frontmatter
# and drops its model pin. So the CLI is asked once per integration, and only the body it writes is
# kept; the frontmatter is the kit's own, byte for byte. The build fails unless the kit's body is whole
# inside the CLI's, with the preset's text before and after it.
#
# Usage:
#   scripts/build-speckit-layer.sh <name>           # rewrite layers/<name>/
#   scripts/build-speckit-layer.sh --check <name>   # fail when layers/<name>/ is not what the CLI generates
#   scripts/build-speckit-layer.sh --compose <kit-skill> <cli-skill> <out> <preset-command>   # one skill, no CLI (for the tests)
#
# Needs the `specify` CLI at exactly KIT_VERSION of build-speckit-kit.sh, and git.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
template="${TEMPLATE_DIR:-$root/template}"
OVERLAY=".specify/speckit-overlay.sha256"
COMMAND_DIR="speckit-specify"
# What the preset's text must hold around the base: one marker for the part before and one for the part after.
BEFORE_MARK="## Before you specify"
AFTER_MARK="## After you specify"

if command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum "$@"; }; else sha256() { shasum -a 256 "$@"; }; fi

# The frontmatter of a skill: the lines from the first --- to the second, inclusive.
frontmatter() { awk '/^---$/{c++} c<2{print} c==2&&/^---$/{print; exit}' "$1"; }
# Its body with no blank line at either end.
body() { awk 'c>=2{print} /^---$/{c++}' "$1" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | sed '/./,$!d'; }

squeeze() { tr -d '[:space:]'; }

# compose <kit skill> <cli skill> <out> <preset command>: the kit's frontmatter, then the CLI's body once it is shown
# to hold the kit's whole with the preset's text, and nothing else, before and after it.
compose() {
  local kit="$1" cli="$2" out="$3" preset="$4" kb cb before after pbefore pafter
  [ "$(frontmatter "$kit" | wc -l)" -ge 2 ] || { echo "error: $kit has no frontmatter" >&2; return 1; }
  kb="$(body "$kit")"; cb="$(body "$cli")"
  [ -n "$kb" ] || { echo "error: $kit has no body" >&2; return 1; }
  [[ "$cb" == *"$kb"* ]] || { echo "error: the CLI's skill does not hold the kit's command whole (a new Spec Kit version? the preset needs a new text)" >&2; return 1; }
  before="${cb%%"$kb"*}"; after="${cb#*"$kb"}"
  [[ "$before" == *"$BEFORE_MARK"* ]] || { echo "error: the preset's text is not before the kit's command" >&2; return 1; }
  [[ "$after" == *"$AFTER_MARK"* ]] || { echo "error: the preset's text is not after the kit's command" >&2; return 1; }
  # The CLI adds a heading before the preset's text; whatever else it adds, or whatever of the preset it loses, fails.
  pbefore="$(sed '/{CORE_TEMPLATE}/,$d' "$preset" | squeeze)"; pafter="$(sed '1,/{CORE_TEMPLATE}/d' "$preset" | squeeze)"
  [ -n "$pbefore" ] && [ -n "$pafter" ] || { echo "error: $preset has no text before and after {CORE_TEMPLATE}" >&2; return 1; }
  before="$(printf '%s' "$before" | squeeze)"; after="$(printf '%s' "$after" | squeeze)"
  [[ "$before" == *"$pbefore" ]] || { echo "error: the text before the kit's command is not the preset's" >&2; return 1; }
  [ "$after" = "$pafter" ] || { echo "error: the text after the kit's command is not the preset's" >&2; return 1; }
  mkdir -p "$(dirname "$out")"
  { frontmatter "$kit"; echo; printf '%s\n' "$cb"; } > "$out"
}

mode=write
case "${1:-}" in
  --compose) [ $# -eq 5 ] || { echo "error: --compose takes <kit-skill> <cli-skill> <out> <preset-command>" >&2; exit 2; }; compose "$2" "$3" "$4" "$5"; exit ;;
  --check) mode=check; shift ;;
  --help|-h) sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  -*) echo "error: unknown argument '$1'" >&2; exit 2 ;;
esac
name="${1:-}"
[[ "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] && [ -d "$root/presets/$name" ] || { echo "error: no preset '${name}' under presets/" >&2; exit 2; }
[ $# -eq 1 ] || { echo "error: one preset name" >&2; exit 2; }

KIT_VERSION="$(sed -n 's/^KIT_VERSION=//p' "$here/build-speckit-kit.sh")"
command -v specify >/dev/null 2>&1 || { echo "error: 'specify' not found on PATH (uv tool install specify-cli --force --from git+https://github.com/github/spec-kit.git@v$KIT_VERSION)" >&2; exit 2; }
have="$(specify version 2>/dev/null | sed -n 's/.*CLI Version[^0-9]*\([0-9][0-9.]*\).*/\1/p')"
[ "$have" = "$KIT_VERSION" ] || { echo "error: the layer is built by Spec Kit $KIT_VERSION, found ${have:-unknown}" >&2; exit 2; }

stage="$(mktemp -d)"; log="$(mktemp)"
trap 'rm -rf "$stage" "$log"' EXIT

for pair in claude:.claude codex:.agents; do
  integration="${pair%%:*}"; dir="${pair#*:}"
  work="$stage/work-$integration"
  mkdir -p "$work"
  tar -cf - -C "$template" .claude/skills .agents/skills .specify | tar -xf - -C "$work"
  if ! ( cd "$work" && git init -q && specify integration use "$integration" && specify preset add --dev "$root/presets/$name" ) >"$log" 2>&1; then
    tail -30 "$log" >&2; echo "error: the CLI could not install the preset for $integration" >&2; exit 1
  fi
  skill="$dir/skills/$COMMAND_DIR/SKILL.md"
  compose "$template/$skill" "$work/$skill" "$stage/layer/$skill" "$root/presets/$name/commands/speckit.specify.md" || exit 1
done

( cd "$stage/layer" && mkdir -p .specify \
  && for f in .agents/skills/$COMMAND_DIR/SKILL.md .claude/skills/$COMMAND_DIR/SKILL.md; do sha256 "$f"; done > "$OVERLAY" )

target="$root/layers/$name"
if [ "$mode" = check ]; then
  if diff -rq "$stage/layer" "$target" >"$log" 2>&1; then echo "layers/$name holds the layer Spec Kit $KIT_VERSION generates"; exit 0; fi
  head -20 "$log" >&2
  echo "error: layers/$name is not the layer Spec Kit $KIT_VERSION generates; run scripts/build-speckit-layer.sh $name" >&2
  exit 1
fi
rm -rf "${target:?}"; mkdir -p "$target"
tar -cf - -C "$stage/layer" . | tar -xf - -C "$target"
echo "layer: $(grep -c . "$target/$OVERLAY") files in layers/$name (Spec Kit $KIT_VERSION)"
