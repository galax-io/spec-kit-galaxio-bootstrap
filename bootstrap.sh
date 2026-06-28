#!/usr/bin/env bash
#
# bootstrap.sh — scaffold a new project from scratch with the standard
# spec-kit + git/milestone development process already wired in.
#
# It lays down:
#   AGENTS.md             generic process (Boundaries/Milestones/Commits/Release) + project placeholders
#   CLAUDE.md             -> @AGENTS.md
#   .claude/settings.json PreToolUse hook wiring (linkage-guard)
#   .claude/hooks/linkage-guard.sh
#   scripts/check-linkage.sh
#   setup-speckit.sh      spec-kit extension/preset installer
#   specs/  .specify/     spec-kit working dirs
#   .gitignore
#
# Usage:
#   bash bootstrap.sh <target-dir> --org <owner/repo> --name "<Project Name>" \
#        [--tagline "<one-liner>"] [--speckit] [--git] [--force]
#
# Flags:
#   --org <owner/repo>  GitHub repo for the milestone gh-api references (substituted into AGENTS.md)
#   --name "<...>"      project name (AGENTS.md title)
#   --tagline "<...>"   one-line description under the title
#   --speckit           also run setup-speckit.sh in the target (needs `specify` CLI + network)
#   --git               git init + initial commit in the target
#   --force             overwrite existing files in target
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

TARGET="" ; ORG="" ; NAME="" ; TAGLINE="" ; DO_SPECKIT=0 ; DO_GIT=0 ; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --org)     shift; ORG="${1:-}" ;;
    --name)    shift; NAME="${1:-}" ;;
    --tagline) shift; TAGLINE="${1:-}" ;;
    --speckit) DO_SPECKIT=1 ;;
    --git)     DO_GIT=1 ;;
    --force)   FORCE=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*)        echo "error: unknown flag '$1'" >&2; exit 2 ;;
    *)         [ -z "$TARGET" ] && TARGET="$1" || { echo "error: unexpected arg '$1'" >&2; exit 2; } ;;
  esac
  shift
done

[ -n "$TARGET" ] || { echo "error: target dir required. See --help." >&2; exit 2; }
[ -n "$NAME" ]   || NAME="$(basename "$TARGET")"
[ -n "$ORG" ]    || ORG="<owner>/<repo>"
[ -n "$TAGLINE" ] || TAGLINE="<one-line description of the project — what it is, who consumes it, what is compatibility-sensitive>"

mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"
echo "==> Scaffolding into: $TARGET"

# copy <src> <dst-rel> — honors --force, refuses to clobber otherwise.
copy() {
  local src="$1" dst="$TARGET/$2"
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    echo "  – skip (exists): $2   (use --force to overwrite)"; return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "  + $2"
}

mkdir -p "$TARGET/specs" "$TARGET/.specify" "$TARGET/.claude/hooks" "$TARGET/scripts"

# AGENTS.md with placeholder substitution (ORG_REPO / PROJECT_NAME / PROJECT_TAGLINE).
agents_dst="$TARGET/AGENTS.md"
if [ -e "$agents_dst" ] && [ "$FORCE" -ne 1 ]; then
  echo "  – skip (exists): AGENTS.md   (use --force to overwrite)"
else
  sed -e "s|{{ORG_REPO}}|$ORG|g" \
      -e "s|{{PROJECT_NAME}}|$NAME|g" \
      -e "s|{{PROJECT_TAGLINE}}|$TAGLINE|g" \
      "$HERE/templates/AGENTS.md" > "$agents_dst"
  echo "  + AGENTS.md (filled: name, tagline, org/repo; other {{...}} left as TODO)"
fi

copy "$HERE/templates/CLAUDE.md"            "CLAUDE.md"
copy "$HERE/templates/claude-settings.json" ".claude/settings.json"
copy "$HERE/templates/gitignore"            ".gitignore"
copy "$HERE/hooks/linkage-guard.sh"         ".claude/hooks/linkage-guard.sh"
copy "$HERE/scripts/check-linkage.sh"       "scripts/check-linkage.sh"
copy "$HERE/setup-speckit.sh"               "setup-speckit.sh"

chmod +x "$TARGET/.claude/hooks/linkage-guard.sh" "$TARGET/scripts/check-linkage.sh" "$TARGET/setup-speckit.sh" 2>/dev/null || true
# keep spec-kit dirs from being empty in git
[ -e "$TARGET/specs/.gitkeep" ]    || : > "$TARGET/specs/.gitkeep"

if [ "$DO_SPECKIT" -eq 1 ]; then
  echo "==> Installing spec-kit extensions/presets"
  ( cd "$TARGET" && bash setup-speckit.sh ) || echo "  ! setup-speckit reported failures (see speckit-install.log)"
fi

if [ "$DO_GIT" -eq 1 ]; then
  echo "==> git init + initial commit"
  ( cd "$TARGET" \
    && git init -q \
    && git add -A \
    && git commit -q -m "chore: scaffold project (spec-kit + process)" \
    && echo "  + initial commit on $(git branch --show-current)" )
fi

cat <<EOF

Done. Next:
  1. Open $TARGET/AGENTS.md and fill the {{...}} placeholders above the '---'
     (Role, Stack, Commands, Structure, Architecture, Test Model).
  2. If not done: install spec-kit -> ( cd "$TARGET" && bash setup-speckit.sh )
  3. Create the GitHub repo as $ORG and its first milestone (vX.Y.0).
EOF
