#!/usr/bin/env bash
#
# adopt.sh — bring the Galaxio process into a repository that was not made from the
# template, without replacing anything the repository already has.
# Run `scripts/adopt.sh --help` for full usage.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${TEMPLATE_DIR:-$here/../template}"

usage() {
  cat <<'EOF'
adopt.sh — bring the Galaxio process into a repository that was not made from the template.

It never replaces a file the repository has:
  AGENTS.md   exists: the "Feature milestones (ALWAYS)" section is inserted before
              "## Commits & PRs" (or appended), and nothing else of the file changes;
              a file that already has the section is left alone.
              missing, but CLAUDE.md holds the project's own guidance (more than a
              pointer to AGENTS.md): the section goes into CLAUDE.md instead, so the
              repository does not get a second source of truth.
              missing otherwise: rendered from the template with copier.
  CLAUDE.md   added when missing, kept otherwise.
  the gate    scripts/check-linkage.sh, its test, .claude/hooks/linkage-guard.sh, its
              test, .githooks/pre-push and its test: each is added when missing;
              one that exists is kept and reported as "same as the template" or
              "differs from the template" so the difference can be reviewed.
              A test is not added next to a script that differs from the template:
              a test belongs to its script.
It never creates .copier-answers.yml: a later `copier update` would take the
differences for local edits.

Usage:
  scripts/adopt.sh [--dry-run] [--org-repo owner/name] [--tagline TEXT] <repository-dir>

Env:
  TEMPLATE_DIR=dir   # the template to read (default: ../template next to this script)

Exit: 0 done | 2 usage/prereq error.
EOF
}

DRY=0
ORG_REPO=""
TAGLINE=""
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY=1 ;;
    --org-repo) shift; ORG_REPO="${1:-}"
                [[ "$ORG_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "error: --org-repo needs owner/name" >&2; exit 2; } ;;
    --tagline)  shift; TAGLINE="${1:-}" ;;
    --help|-h)  usage; exit 0 ;;
    -*)         echo "error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
    *)          [ -z "$TARGET" ] || { echo "error: one repository at a time" >&2; exit 2; }; TARGET="$1" ;;
  esac
  shift
done

[ -n "$TARGET" ] || { echo "error: name the repository directory" >&2; usage >&2; exit 2; }
[ -d "$TARGET" ] || { echo "error: '$TARGET' is not a directory" >&2; exit 2; }
[ -f "$TEMPLATE_DIR/AGENTS.md.jinja" ] || { echo "error: no template at '$TEMPLATE_DIR' (AGENTS.md.jinja missing)" >&2; exit 2; }
TARGET="$(cd "$TARGET" && pwd)"

if [ -z "$ORG_REPO" ]; then
  remote="$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)"
  ORG_REPO="$(sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##' <<<"$remote")"
  [[ "$ORG_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || ORG_REPO="galax-io/$(basename "$TARGET")"
fi
NAME="${ORG_REPO#*/}"

[ "$DRY" = 1 ] && echo "dry run: nothing is written"
echo "Repository: $TARGET ($ORG_REPO)"

# The section, from the template: its heading down to the next "## " heading, no trailing blank lines.
section="$(awk '
  /^## Feature milestones \(ALWAYS\)/ { on = 1; print; next }
  on && /^## / { exit }
  on { print }
' "$TEMPLATE_DIR/AGENTS.md.jinja" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
[ -n "$section" ] || { echo "error: the template has no 'Feature milestones (ALWAYS)' section" >&2; exit 2; }

rendered=""
render() { # renders the template once into a temp dir; sets $rendered
  [ -n "$rendered" ] && return 0
  command -v copier >/dev/null 2>&1 || { echo "error: 'copier' not found on PATH (needed to create AGENTS.md or CLAUDE.md)" >&2; exit 2; }
  rendered="$(mktemp -d)"
  trap 'rm -rf "$rendered"' EXIT
  local src
  src="$(dirname "$TEMPLATE_DIR")"
  local data=(--data "project_name=$NAME" --data "org_repo=$ORG_REPO" --data run_speckit=false --data do_git=false)
  [ -z "$TAGLINE" ] || data+=(--data "project_tagline=$TAGLINE")
  # From a git checkout copier would render the latest tag; HEAD is the template at hand.
  if git -C "$src" rev-parse --git-dir >/dev/null 2>&1; then
    copier copy --trust --defaults --vcs-ref=HEAD "${data[@]}" "$src" "$rendered" >/dev/null 2>&1 \
      || { echo "error: copier could not render the template" >&2; exit 2; }
  else
    copier copy --trust --defaults "${data[@]}" "$src" "$rendered" >/dev/null 2>&1 \
      || { echo "error: copier could not render the template" >&2; exit 2; }
  fi
}

put() { # relative path, source file — add a file that is missing
  [ "$DRY" = 1 ] || { mkdir -p "$(dirname "$TARGET/$1")"; cp -p "$2" "$TARGET/$1"; }
  echo "added: $1"
}

# The file that holds the project's instructions: AGENTS.md, else a CLAUDE.md that says
# more than "@AGENTS.md". The section goes into it; the rest of the file is not touched.
instr=""
if [ -f "$TARGET/AGENTS.md" ]; then
  instr="AGENTS.md"
elif [ -f "$TARGET/CLAUDE.md" ] && grep -qvE '^[[:space:]]*(#.*|@AGENTS\.md)?[[:space:]]*$' "$TARGET/CLAUDE.md"; then
  instr="CLAUDE.md"
fi

if [ -n "$instr" ]; then
  if grep -q '^## Feature milestones' "$TARGET/$instr"; then
    echo "kept: $instr (has Feature milestones)"
  else
    if [ "$DRY" = 0 ]; then
      tmp="$(mktemp)"; secfile="$(mktemp)"
      echo "$section" > "$secfile"   # awk -v cannot carry newlines on every awk
      if grep -q '^## Commits & PRs' "$TARGET/$instr"; then
        awk -v secfile="$secfile" '/^## Commits & PRs/ && !done { while ((getline line < secfile) > 0) print line; print ""; done = 1 } { print }' "$TARGET/$instr" > "$tmp"
      else
        { cat "$TARGET/$instr"; [ -z "$(tail -c1 "$TARGET/$instr")" ] || echo; echo; echo "$section"; } > "$tmp"
      fi
      cat "$tmp" > "$TARGET/$instr"   # keeps the file's mode and owner
      rm -f "$tmp" "$secfile"
    fi
    echo "inserted: $instr (Feature milestones)"
  fi
else
  render
  put AGENTS.md "$rendered/AGENTS.md"
fi

# CLAUDE.md: added when missing.
if [ -f "$TARGET/CLAUDE.md" ]; then
  echo "kept: CLAUDE.md"
else
  render
  put CLAUDE.md "$rendered/CLAUDE.md"
fi

# The gate: each file is added when missing and otherwise only compared.
for f in scripts/check-linkage.sh scripts/check-linkage_test.sh \
         .claude/hooks/linkage-guard.sh .claude/hooks/linkage-guard_test.sh \
         .githooks/pre-push .githooks/pre-push_test.sh; do
  # A test belongs to its script: next to a script that differs from the template, the
  # template's test would assert behaviour the script lacks.
  script="${f%_test.sh}.sh"
  if [ ! -e "$TARGET/$f" ] && [ "$script" != "$f" ] && [ "${f##*/}" != "pre-push_test.sh" ] \
     && [ -e "$TARGET/$script" ] && ! cmp -s "$TARGET/$script" "$TEMPLATE_DIR/$script"; then
    echo "skipped: $f (its script differs from the template)"
  elif [ ! -e "$TARGET/$f" ] && [ "${f##*/}" = "pre-push_test.sh" ] \
     && [ -e "$TARGET/.githooks/pre-push" ] && ! cmp -s "$TARGET/.githooks/pre-push" "$TEMPLATE_DIR/.githooks/pre-push"; then
    echo "skipped: $f (its script differs from the template)"
  elif [ ! -e "$TARGET/$f" ]; then
    put "$f" "$TEMPLATE_DIR/$f"
  elif cmp -s "$TARGET/$f" "$TEMPLATE_DIR/$f"; then
    echo "kept: $f (same as the template)"
  else
    echo "kept: $f (differs from the template)"
  fi
done

echo
echo "Not touched: .copier-answers.yml, .claude/settings.json (which registers the hook), setup-speckit.sh."
