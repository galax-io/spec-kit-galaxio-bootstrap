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
              "## Commits & PRs" (or appended), the "Labels (ALWAYS)" section right
              after it, and nothing else of the file changes; a section the file
              already has is left alone.
              missing, but CLAUDE.md holds the project's own guidance (more than a
              pointer to AGENTS.md): the sections go into CLAUDE.md instead, so the
              repository does not get a second source of truth.
              missing otherwise: rendered from the template with copier.
  CLAUDE.md   added when missing, kept otherwise.
  the PR check  .github/workflows/linkage.yml runs the gate on every pull request; it is not
              added when a workflow of the repository already runs `check-linkage.sh --pr`.
  the gate    scripts/check-linkage.sh, its test, .claude/hooks/linkage-guard.sh, its
              test, .githooks/pre-push and its test: each is added when missing;
              one that exists is kept and reported as "same as the template" or
              "differs from the template" so the difference can be reviewed.
              A test is not added next to a script that differs from the template:
              a test belongs to its script.
It never creates .copier-answers.yml: a later `copier update` would take the
differences for local edits.

--refresh   also bring what an earlier run of this script put there up to the current
              template: a gate file, or one of the two sections, that equals the
              template of some released tag is replaced by the current one ("updated:");
              one that equals no release is a local variant and is kept ("kept:").
              Needs the template's git history (a checkout of the bootstrap repository).

--speckit   only the Spec Kit kit, and unlike the rest it REPLACES: the repository gets the
              template's skills (.claude/skills/speckit-*, .agents/skills/speckit-*) and
              .specify/ byte for byte, so that every repository holds the same ones. A file
              that differs is replaced ("updated:"), a file the kit does not have in the
              directories it owns is removed ("removed:"), and so is the Specify CLI's state
              (registries, cache, backups, integration manifests), which the kit does not
              ship. Added, with the kit: .specify/speckit-kit.sha256, scripts/check-speckit.sh,
              its test, .github/workflows/speckit.yml. Never touched: .specify/memory/ (the
              constitution; its starting point is added only when missing), .specify/feature.json,
              skills that are not speckit-* ones, and setup-speckit.sh (reported as obsolete).
              Nothing else of the usual run happens. Run it again after every new template
              release; with copier, `copier update` brings the same files.

Usage:
  scripts/adopt.sh [--dry-run] [--refresh] [--org-repo owner/name] [--tagline TEXT] <repository-dir>
  scripts/adopt.sh [--dry-run] --speckit <repository-dir>

Env:
  TEMPLATE_DIR=dir   # the template to read (default: ../template next to this script)

Exit: 0 done | 2 usage/prereq error.
EOF
}

DRY=0
REFRESH=0
SPECKIT=0
ORG_REPO=""
TAGLINE=""
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY=1 ;;
    --refresh)  REFRESH=1 ;;
    --speckit)  SPECKIT=1 ;;
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
SRC="$(dirname "$TEMPLATE_DIR")"
if [ "$REFRESH" = 1 ] && ! git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: --refresh needs the template's git history (tags of released versions); '$SRC' is not a git checkout" >&2
  exit 2
fi

if [ -z "$ORG_REPO" ]; then
  remote="$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)"
  ORG_REPO="$(sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##' <<<"$remote")"
  [[ "$ORG_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || ORG_REPO="galax-io/$(basename "$TARGET")"
fi
NAME="${ORG_REPO#*/}"

[ "$DRY" = 1 ] && echo "dry run: nothing is written"
echo "Repository: $TARGET ($ORG_REPO)"

# --speckit: the Spec Kit kit, byte for byte, and nothing else.
if [ "$SPECKIT" = 1 ]; then
  KIT_MANIFEST=".specify/speckit-kit.sha256"
  [ -f "$TEMPLATE_DIR/$KIT_MANIFEST" ] || { echo "error: the template has no Spec Kit kit ($KIT_MANIFEST missing); generate it with scripts/build-speckit-kit.sh" >&2; exit 2; }
  added=0; updated=0; removed=0; same=0
  listed="$(mktemp)"; found="$(mktemp)"
  trap 'rm -f "$listed" "$found"' EXIT

  kit_put() { # path — make $TARGET/path the template's file
    local path="$1" src="$TEMPLATE_DIR/$1"
    [ -f "$src" ] || { echo "error: $path is in the kit but not in the template" >&2; exit 2; }
    if [ ! -e "$TARGET/$path" ]; then
      added=$((added + 1))
    elif cmp -s "$src" "$TARGET/$path"; then
      same=$((same + 1)); return 0
    else
      updated=$((updated + 1)); echo "updated: $path"
    fi
    [ "$DRY" = 1 ] || { mkdir -p "$(dirname "$TARGET/$path")"; cp -p "$src" "$TARGET/$path"; }
  }
  kit_remove() { # path
    removed=$((removed + 1)); echo "removed: $1"
    [ "$DRY" = 1 ] || rm -f "$TARGET/$1"
  }

  # The files of the kit, and the file that lists them.
  while read -r _hash path; do
    [ -n "$path" ] || continue
    printf '%s\n' "$path" >> "$listed"
    kit_put "$path"
  done < "$TEMPLATE_DIR/$KIT_MANIFEST"
  printf '%s\n' "$KIT_MANIFEST" >> "$listed"
  kit_put "$KIT_MANIFEST"
  # What goes with the kit: its check, the check's test, the workflow that runs it.
  for f in scripts/check-speckit.sh scripts/check-speckit_test.sh .github/workflows/speckit.yml; do
    if [ -f "$TEMPLATE_DIR/$f" ]; then kit_put "$f"; fi
  done
  # The constitution is the repository's own: its starting point only when there is none.
  for f in .specify/memory/constitution.md .specify/memory/.constitution-template.json; do
    if [ -f "$TEMPLATE_DIR/$f" ] && [ ! -e "$TARGET/$f" ]; then kit_put "$f"; fi
  done

  # The Specify CLI's state: it differs on every run, the kit does not ship it.
  state="$(mktemp)"
  ( cd "$TARGET" && {
      for f in .specify/extensions/.registry .specify/presets/.registry .specify/workflows/workflow-registry.json; do
        if [ -f "$f" ]; then echo "$f"; fi
      done
      for d in .specify/extensions/.cache .specify/extensions/.backup; do
        if [ -d "$d" ]; then find "$d" -type f; fi
      done
      if [ -d .specify/integrations ]; then find .specify/integrations -maxdepth 1 -type f -name '*.manifest.json'; fi
    } | LC_ALL=C sort ) > "$state"
  while read -r f; do
    kit_remove "$f"
  done < "$state"
  rm -f "$state"

  # What the kit owns and does not list: a skill or a script of an older Spec Kit.
  sort -o "$listed" "$listed"
  ( cd "$TARGET" && for d in .claude/skills/speckit-* .agents/skills/speckit-* .specify/scripts .specify/templates \
        .specify/extensions .specify/presets .specify/workflows .specify/integrations; do
      [ -e "$d" ] || continue
      find "$d" -type f \
        ! -path '*/__pycache__/*' ! -name '*.pyc' ! -path '.specify/extensions/.registry' ! -path '.specify/extensions/.cache/*' ! -path '.specify/extensions/.backup/*' \
        ! -path '.specify/extensions/*/local-config.yml' ! -path '.specify/presets/.registry' \
        ! -path '.specify/integrations/*.manifest.json' ! -path '.specify/integrations/packages/*' \
        ! -path '.specify/integrations/packages.json' ! -path '.specify/workflows/workflow-registry.json'
    done | LC_ALL=C sort ) > "$found"
  while read -r f; do
    kit_remove "$f"
  done < <(LC_ALL=C comm -23 "$found" "$listed")
  if [ "$DRY" = 0 ]; then
    ( cd "$TARGET" && for d in .claude/skills .agents/skills .specify; do [ -d "$d" ] && find "$d" -type d -empty -delete; done ) || true
  fi

  echo "kit: $added added, $updated updated, $removed removed, $same unchanged"
  [ ! -e "$TARGET/setup-speckit.sh" ] || echo "note: setup-speckit.sh is obsolete (the kit is generated in spec-kit-galaxio-bootstrap, nothing installs Spec Kit here); delete it"
  exit 0
fi

# The sections the process adds to a project's instructions.
FEATURES="Feature milestones (ALWAYS)"
LABELS="Labels (ALWAYS)"

section_of() { # heading; file on stdin — the section: its heading down to the next "## " heading, no trailing blank lines
  awk -v h="## $1" '
    index($0, h) == 1 { on = 1; print; next }
    on && /^## / { exit }
    on { print }
  ' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}
for heading in "$FEATURES" "$LABELS"; do
  [ -n "$(section_of "$heading" < "$TEMPLATE_DIR/AGENTS.md.jinja")" ] \
    || { echo "error: the template has no '$heading' section" >&2; exit 2; }
done

# The tag whose template put exactly this content at this path, if any (--refresh).
released_tag() { # path inside the template, file to compare
  local tag
  for tag in $(git -C "$SRC" tag --sort=version:refname); do
    if git -C "$SRC" show "$tag:template/$1" 2>/dev/null | cmp -s - "$2"; then echo "$tag"; return 0; fi
  done
  return 1
}

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
# more than "@AGENTS.md". The sections go into it; the rest of the file is not touched.
instr=""
if [ -f "$TARGET/AGENTS.md" ]; then
  instr="AGENTS.md"
elif [ -f "$TARGET/CLAUDE.md" ] && grep -qvE '^[[:space:]]*(#.*|@AGENTS\.md)?[[:space:]]*$' "$TARGET/CLAUDE.md"; then
  instr="CLAUDE.md"
fi

# One section of the template into $instr. Missing: inserted before line $2, or appended
# when $2 is empty. Present: kept; with --refresh, a section equal to that of a released
# template is replaced by the current one.
sync_section() { # heading, line the section goes before
  local heading="$1" name="${1% (ALWAYS)}" text mine old="" tag tmp secfile
  text="$(section_of "$heading" < "$TEMPLATE_DIR/AGENTS.md.jinja")"
  if grep -q "^## $name" "$TARGET/$instr"; then
    mine="$(section_of "$heading" < "$TARGET/$instr")"
    if [ "$REFRESH" = 0 ] || [ "$mine" = "$text" ]; then
      echo "kept: $instr (has $name)"; return 0
    fi
    # An empty one is a heading of the project's own, not the section of a release that had none.
    if [ -n "$mine" ]; then
      for tag in $(git -C "$SRC" tag --sort=version:refname); do
        if [ "$(git -C "$SRC" show "$tag:template/AGENTS.md.jinja" 2>/dev/null | section_of "$heading")" = "$mine" ]; then old="$tag"; break; fi
      done
    fi
    if [ -z "$old" ]; then
      echo "kept: $instr ($name differs from every released template; review by hand)"; return 0
    fi
    if [ "$DRY" = 0 ]; then
      tmp="$(mktemp)"; secfile="$(mktemp)"; echo "$text" > "$secfile"
      awk -v h="## $heading" -v secfile="$secfile" '
        index($0, h) == 1 && !done { while ((getline line < secfile) > 0) print line; print ""; done = 1; skip = 1; next }
        skip && /^## / { skip = 0 }
        !skip { print }
      ' "$TARGET/$instr" > "$tmp"
      cat "$tmp" > "$TARGET/$instr"; rm -f "$tmp" "$secfile"
    fi
    echo "updated: $instr ($name was the template of $old)"
  else
    if [ "$DRY" = 0 ]; then
      tmp="$(mktemp)"; secfile="$(mktemp)"
      echo "$text" > "$secfile"   # awk -v cannot carry newlines on every awk
      if [ -n "$2" ]; then
        awk -v at="$2" -v secfile="$secfile" 'NR == at { while ((getline line < secfile) > 0) print line; print "" } { print }' "$TARGET/$instr" > "$tmp"
      else
        { cat "$TARGET/$instr"; [ -z "$(tail -c1 "$TARGET/$instr")" ] || echo; echo; echo "$text"; } > "$tmp"
      fi
      cat "$tmp" > "$TARGET/$instr"   # keeps the file's mode and owner
      rm -f "$tmp" "$secfile"
    fi
    echo "inserted: $instr ($name)"
  fi
}

if [ -n "$instr" ]; then
  # Feature milestones goes before "## Commits & PRs"; Labels right after Feature milestones.
  sync_section "$FEATURES" "$(awk '/^## Commits & PRs/ { print NR; exit }' "$TARGET/$instr")"
  sync_section "$LABELS" "$(awk 'on && /^## / { print NR; exit } /^## Feature milestones/ { on = 1 }' "$TARGET/$instr")"
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
  elif [ "$REFRESH" = 1 ]; then
    if old="$(released_tag "$f" "$TARGET/$f")"; then
      [ "$DRY" = 1 ] || cp -p "$TEMPLATE_DIR/$f" "$TARGET/$f"
      echo "updated: $f (was the template of $old)"
    else
      echo "kept: $f (differs from every released template)"
    fi
  else
    echo "kept: $f (differs from the template)"
  fi
done

# The PR check: a workflow that runs the gate on pull requests, unless the repository has one already.
WF=".github/workflows/linkage.yml"
if [ -d "$TARGET/.github/workflows" ] && existing="$(grep -lE 'check-linkage\.sh[^|]*--pr' "$TARGET"/.github/workflows/*.y*ml 2>/dev/null | grep -v "/linkage\.yml$" | head -n1)" && [ -n "$existing" ]; then
  echo "kept: .github/workflows/$(basename "$existing") (already runs the PR gate)"
elif [ ! -e "$TARGET/$WF" ]; then
  put "$WF" "$TEMPLATE_DIR/$WF"
elif cmp -s "$TARGET/$WF" "$TEMPLATE_DIR/$WF"; then
  echo "kept: $WF (same as the template)"
elif [ "$REFRESH" = 1 ] && old="$(released_tag "$WF" "$TARGET/$WF")"; then
  [ "$DRY" = 1 ] || cp -p "$TEMPLATE_DIR/$WF" "$TARGET/$WF"
  echo "updated: $WF (was the template of $old)"
else
  echo "kept: $WF (differs from the template)"
fi

echo
echo "Not touched: .copier-answers.yml, .claude/settings.json (which registers the hook), setup-speckit.sh."
