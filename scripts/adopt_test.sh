#!/usr/bin/env bash
#
# adopt_test.sh — tests for scripts/adopt.sh.
#
# Hermetic: TEMPLATE_DIR points at a tiny fake template, and a stub `copier` on PATH
# renders the two files the script asks it for. What is under test is the promise of
# adopt.sh: it brings the process into a repository that was not made from the
# template WITHOUT replacing anything the repository already has — a file that exists
# is kept byte for byte, the Feature milestones and Labels sections are inserted into an
# existing AGENTS.md and nothing else of it changes, files that are missing are added,
# and running it twice changes nothing.

# shellcheck disable=SC2046
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/adopt.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { printf '  ✓ %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  ✗ %s\n     %s\n' "$1" "$2"; fail=$((fail + 1)); }
check() { # description, condition-exit-code, detail
  if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "$3"; fi
}

# ---- the fake template and the stub copier -----------------------------------------
tpl="$tmp/template"
mkdir -p "$tpl/scripts" "$tpl/.claude/hooks" "$tpl/.githooks" "$tpl/.github/workflows"
printf 'name: linkage\n# template\n' > "$tpl/.github/workflows/linkage.yml"
cat > "$tpl/AGENTS.md.jinja" <<'EOF'
# {{ project_name }} — Agent Guide

## Milestones (ALWAYS)

Every piece of work is tied to a milestone.

## Feature milestones (ALWAYS)

A feature is an issue in the backlog.

- **Feature issue.** Lists the work.
- **Release.** Publish when done.

## Labels (ALWAYS)

One label scheme for every repository.

- **Names.** Every label is `group:value`.

## Commits & PRs

- One concern per PR.
EOF
printf '# {{ project_name }}\n' > "$tpl/CLAUDE.md.jinja"
for f in scripts/check-linkage.sh scripts/check-linkage_test.sh .claude/hooks/linkage-guard.sh \
         .claude/hooks/linkage-guard_test.sh .githooks/pre-push .githooks/pre-push_test.sh; do
  printf '#!/usr/bin/env bash\n# template %s\n' "$f" > "$tpl/$f"
  chmod +x "$tpl/$f"
done

bin="$tmp/bin"; mkdir -p "$bin"
cat > "$bin/copier" <<'STUB'
#!/usr/bin/env bash
# stub: copier copy ... <src> <dest> — renders AGENTS.md and CLAUDE.md the way the template would
echo "copier $*" >> "${COPIER_LOG:?}"
dest="${*: -1}"
mkdir -p "$dest"
printf '# rendered AGENTS.md\n\n## Feature milestones (ALWAYS)\n\nrendered\n' > "$dest/AGENTS.md"
printf '# rendered CLAUDE.md\n' > "$dest/CLAUDE.md"
STUB
chmod +x "$bin/copier"

new_repo() { # name — an empty repository directory
  repo="$tmp/repo-$1"; rm -rf "$repo"; mkdir -p "$repo"
}
write() { # path, content — a file of the repository
  mkdir -p "$(dirname "$repo/$1")"; printf '%s' "$2" > "$repo/$1"
}
run() { # adopt.sh arguments; sets $out and $rc
  : > "$tmp/copier.log"
  out="$(PATH="$bin:$PATH" TEMPLATE_DIR="$tpl" COPIER_LOG="$tmp/copier.log" bash "$script" "$@" 2>&1)"; rc=$?
}
has() { grep -qF -- "$1" <<<"$out"; }
snapshot() { (cd "$repo" && find . -type f | sort | xargs shasum 2>/dev/null); }

echo "adopt.sh"

# 1. an existing AGENTS.md gets the section before "Commits & PRs", and nothing else changes
new_repo insert
write AGENTS.md $'# Mine\n\nProject-specific text.\n\n## Milestones (ALWAYS)\n\nOur own rule: one milestone, one PR.\n\n## Commits & PRs\n\n- Our commit rule.\n'
run "$repo"
check "insert: the run succeeds" $([ "$rc" -eq 0 ] && echo 0 || echo 1) "rc=$rc out=$out"
check "insert: the section is in AGENTS.md" $(grep -q '^## Feature milestones (ALWAYS)' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "insert: it sits before Commits & PRs" $(awk '/^## Feature milestones/{f=NR} /^## Commits & PRs/{c=NR} END{exit !(f && c && f < c)}' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "insert: the repository's own text is untouched" $(grep -qF 'Our own rule: one milestone, one PR.' "$repo/AGENTS.md" && grep -qF -- '- Our commit rule.' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
added=$(diff <(printf '# Mine\n\nProject-specific text.\n\n## Milestones (ALWAYS)\n\nOur own rule: one milestone, one PR.\n\n## Commits & PRs\n\n- Our commit rule.\n') "$repo/AGENTS.md" | grep -c '^<' || true)
check "insert: no line of the original is removed or changed" $([ "$added" -eq 0 ] && echo 0 || echo 1) "removed/changed lines: $added"
check "insert: the section text is the template's" $(grep -qF -- '- **Release.** Publish when done.' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "insert: it reports the insertion" $(has 'inserted: AGENTS.md (Feature milestones)' && echo 0 || echo 1) "out=$out"
check "insert: the Labels section follows Feature milestones, before Commits & PRs" $(awk '/^## Feature milestones/{f=NR} /^## Labels/{l=NR} /^## Commits & PRs/{c=NR} END{exit !(f && l && c && f < l && l < c)}' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "insert: the Labels text is the template's" $(grep -qF -- '- **Names.** Every label is `group:value`.' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "insert: it reports the Labels insertion" $(has 'inserted: AGENTS.md (Labels)' && echo 0 || echo 1) "out=$out"

# 2. an AGENTS.md that already has both sections is left alone
new_repo has-section
write AGENTS.md $'# Mine\n\n## Feature milestones (ALWAYS)\n\nOur edited version.\n\n## Labels (ALWAYS)\n\nOur labels.\n\n## Commits & PRs\n'
before=$(snapshot)
run "$repo"
check "has-section: AGENTS.md is not changed" $([ "$(snapshot | grep AGENTS.md)" = "$(grep AGENTS.md <<<"$before")" ] && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "has-section: it says the section is there" $(has 'kept: AGENTS.md (has Feature milestones)' && echo 0 || echo 1) "out=$out"
check "has-section: it says the Labels section is there" $(has 'kept: AGENTS.md (has Labels)' && echo 0 || echo 1) "out=$out"

# 2b. an AGENTS.md adopted before the Labels section existed: Labels goes right after
#     Feature milestones, which is kept, and nothing else changes
new_repo labels-after
labels_before=$'# Mine\n\n## Feature milestones (ALWAYS)\n\nOur edited version.\n\n## Our own section\n\nOur text.\n\n## Commits & PRs\n'
write AGENTS.md "$labels_before"
run "$repo"
check "labels-after: Labels sits right after Feature milestones" $(awk '/^## Feature milestones/{f=NR} /^## Labels/{l=NR} /^## Our own section/{o=NR} END{exit !(f && l && o && f < l && l < o)}' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "labels-after: Feature milestones is kept as the repository wrote it" $(grep -qF 'Our edited version.' "$repo/AGENTS.md" && ! grep -qF 'A feature is an issue in the backlog.' "$repo/AGENTS.md" && has 'kept: AGENTS.md (has Feature milestones)' && echo 0 || echo 1) "out=$out"
removed=$(diff <(printf '%s' "$labels_before") "$repo/AGENTS.md" | grep -c '^<' || true)
check "labels-after: no line of the original is removed or changed" $([ "$removed" -eq 0 ] && echo 0 || echo 1) "removed/changed lines: $removed"
check "labels-after: it reports the Labels insertion" $(has 'inserted: AGENTS.md (Labels)' && echo 0 || echo 1) "out=$out"

# 3. no "Commits & PRs" heading: the sections are appended
new_repo append
write AGENTS.md $'# Mine\n\nOnly this.\n'
run "$repo"
check "append: Feature milestones and then Labels are added at the end" $(awk '/^## /{p=q; q=$0} END{exit !(p ~ /^## Feature milestones/ && q ~ /^## Labels/)}' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "append: the original text is still first" $(head -n 3 "$repo/AGENTS.md" | grep -qF 'Only this.' && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"

# 4. no AGENTS.md: it is rendered by copier, with the CLAUDE.md that goes with it
new_repo render
run "$repo" --org-repo galax-io/thing
check "render: AGENTS.md is created" $([ -f "$repo/AGENTS.md" ] && echo 0 || echo 1) "out=$out"
check "render: CLAUDE.md is created" $([ -f "$repo/CLAUDE.md" ] && echo 0 || echo 1) "out=$out"
check "render: copier is asked for the project name and the org repo" $(grep -q 'org_repo=galax-io/thing' "$tmp/copier.log" && grep -q 'project_name=thing' "$tmp/copier.log" && echo 0 || echo 1) "$(cat "$tmp/copier.log")"
check "render: it reports the added files" $(has 'added: AGENTS.md' && has 'added: CLAUDE.md' && echo 0 || echo 1) "out=$out"

# 5. no AGENTS.md but a CLAUDE.md with the project's own guidance: the section goes into
#    CLAUDE.md, no second AGENTS.md is created, and the guidance is untouched
new_repo claude-guidance
write CLAUDE.md $'# Project\n\nOur own guidance.\n\n## Commits & PRs\n\n- ours\n'
run "$repo"
check "claude-guidance: the section is inserted into CLAUDE.md" $(grep -q '^## Feature milestones (ALWAYS)' "$repo/CLAUDE.md" && echo 0 || echo 1) "$(cat "$repo/CLAUDE.md")"
check "claude-guidance: the guidance is untouched" $(grep -qF 'Our own guidance.' "$repo/CLAUDE.md" && grep -qF -- '- ours' "$repo/CLAUDE.md" && echo 0 || echo 1) "$(cat "$repo/CLAUDE.md")"
check "claude-guidance: no AGENTS.md is created" $([ ! -e "$repo/AGENTS.md" ] && echo 0 || echo 1) "out=$out"
check "claude-guidance: it reports the insertion" $(has 'inserted: CLAUDE.md (Feature milestones)' && echo 0 || echo 1) "out=$out"
check "claude-guidance: the Labels section goes into CLAUDE.md too" $(grep -q '^## Labels (ALWAYS)' "$repo/CLAUDE.md" && has 'inserted: CLAUDE.md (Labels)' && echo 0 || echo 1) "$(cat "$repo/CLAUDE.md")"

# 5b. a CLAUDE.md that only points at AGENTS.md is no guidance: AGENTS.md is rendered
new_repo claude-pointer
write CLAUDE.md $'# CLAUDE.md\n\n@AGENTS.md\n'
run "$repo"
check "claude-pointer: AGENTS.md is rendered" $([ -f "$repo/AGENTS.md" ] && echo 0 || echo 1) "out=$out"
check "claude-pointer: the pointer is kept as it is" $([ "$(cat "$repo/CLAUDE.md")" = $'# CLAUDE.md\n\n@AGENTS.md' ] && echo 0 || echo 1) "$(cat "$repo/CLAUDE.md")"

# 5c. the project tagline reaches copier
new_repo tagline
run --tagline "Does the thing" "$repo"
check "tagline: copier is given the project tagline" $(grep -q 'project_tagline=Does the thing' "$tmp/copier.log" && echo 0 || echo 1) "$(cat "$tmp/copier.log")"

# 6. process files that are missing are added, executable; the answers file is never created
new_repo files
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
run "$repo"
check "files: the linkage script is added" $([ -f "$repo/scripts/check-linkage.sh" ] && echo 0 || echo 1) "out=$out"
check "files: it is executable" $([ -x "$repo/scripts/check-linkage.sh" ] && echo 0 || echo 1) "out=$out"
check "files: the hooks are added" $([ -f "$repo/.claude/hooks/linkage-guard.sh" ] && [ -f "$repo/.githooks/pre-push" ] && echo 0 || echo 1) "out=$out"
check "files: no .copier-answers.yml is created" $([ ! -e "$repo/.copier-answers.yml" ] && echo 0 || echo 1) "out=$out"
check "files: the added files are reported" $(has 'added: scripts/check-linkage.sh' && echo 0 || echo 1) "out=$out"

# 7. a file that exists and differs is kept byte for byte and named as different
new_repo differs
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
write scripts/check-linkage.sh $'#!/usr/bin/env bash\n# my own, ahead of the template\n'
run "$repo"
check "differs: the file is untouched" $([ "$(cat "$repo/scripts/check-linkage.sh")" = $'#!/usr/bin/env bash\n# my own, ahead of the template' ] && echo 0 || echo 1) "$(cat "$repo/scripts/check-linkage.sh")"
check "differs: it is reported as kept and different" $(has 'kept: scripts/check-linkage.sh (differs from the template)' && echo 0 || echo 1) "out=$out"
check "differs: the other missing files are still added" $([ -f "$repo/.githooks/pre-push" ] && echo 0 || echo 1) "out=$out"

# 7b. a test belongs to its script: when the script exists and differs from the template,
#     the template's test for it is not added (it would test behaviour the script lacks)
new_repo test-follows-script
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
write scripts/check-linkage.sh $'#!/usr/bin/env bash\n# my own, ahead of the template\n'
run "$repo"
check "test-follows-script: the template's test is not added next to a different script" $([ ! -e "$repo/scripts/check-linkage_test.sh" ] && echo 0 || echo 1) "out=$out"
check "test-follows-script: it says why" $(has 'skipped: scripts/check-linkage_test.sh (its script differs from the template)' && echo 0 || echo 1) "out=$out"
check "test-follows-script: the other tests are still added" $([ -f "$repo/.githooks/pre-push_test.sh" ] && [ -f "$repo/.claude/hooks/linkage-guard_test.sh" ] && echo 0 || echo 1) "out=$out"
new_repo test-follows-same
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
mkdir -p "$repo/scripts"; cp "$tpl/scripts/check-linkage.sh" "$repo/scripts/check-linkage.sh"
run "$repo"
check "test-follows-same: next to an identical script the test is added" $([ -f "$repo/scripts/check-linkage_test.sh" ] && echo 0 || echo 1) "out=$out"
new_repo test-own
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
write scripts/check-linkage.sh $'#!/usr/bin/env bash\n# my own\n'
write scripts/check-linkage_test.sh $'#!/usr/bin/env bash\n# my own test\n'
run "$repo"
check "test-own: a test the repository has is kept, whatever the script" $([ "$(cat "$repo/scripts/check-linkage_test.sh")" = $'#!/usr/bin/env bash\n# my own test' ] && has 'kept: scripts/check-linkage_test.sh (differs from the template)' && echo 0 || echo 1) "out=$out"

# 8. a file identical to the template is reported as the same
new_repo same
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
mkdir -p "$repo/scripts"; cp "$tpl/scripts/check-linkage.sh" "$repo/scripts/check-linkage.sh"
run "$repo"
check "same: an identical file is reported as the same" $(has 'kept: scripts/check-linkage.sh (same as the template)' && echo 0 || echo 1) "out=$out"

# 9. --dry-run reports and writes nothing
new_repo dry
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
before=$(snapshot)
run --dry-run "$repo"
check "dry-run: nothing is written" $([ "$(snapshot)" = "$before" ] && echo 0 || echo 1) "$(snapshot)"
check "dry-run: it still reports what it would do" $(has 'inserted: AGENTS.md (Feature milestones)' && has 'inserted: AGENTS.md (Labels)' && has 'added: scripts/check-linkage.sh' && echo 0 || echo 1) "out=$out"
check "dry-run: it says it is a dry run" $(has 'dry run' && echo 0 || echo 1) "out=$out"

# 10. a second run changes nothing
new_repo twice
write AGENTS.md $'# Mine\n\n## Commits & PRs\n\n- ours\n'
run "$repo"
before=$(snapshot)
run "$repo"
check "twice: the second run changes no file" $([ "$(snapshot)" = "$before" ] && echo 0 || echo 1) "$(diff <(echo "$before") <(snapshot))"
check "twice: it adds and inserts nothing" $(! has 'added:' && ! has 'inserted:' && echo 0 || echo 1) "out=$out"

# 11. usage errors
run
check "usage: no argument fails with 2" $([ "$rc" -eq 2 ] && echo 0 || echo 1) "rc=$rc out=$out"
run "$tmp/does-not-exist"
check "usage: a missing directory fails with 2" $([ "$rc" -eq 2 ] && echo 0 || echo 1) "rc=$rc out=$out"
run --help
check "usage: --help exits 0 and shows usage" $([ "$rc" -eq 0 ] && has 'Usage:' && echo 0 || echo 1) "rc=$rc out=$out"
new_repo no-template
out="$(PATH="$bin:$PATH" TEMPLATE_DIR="$tmp/nope" COPIER_LOG="$tmp/copier.log" bash "$script" "$repo" 2>&1)"; rc=$?
check "usage: a missing template directory fails with 2" $([ "$rc" -eq 2 ] && echo 0 || echo 1) "rc=$rc out=$out"

# ---- --refresh: bring gate files and the section up to the current template, but only ----
# ---- those that equal a released version of the template; a local variant is kept ---------
tpl2="$tmp/tpl2"; mkdir -p "$tpl2/template/scripts" "$tpl2/template/.claude/hooks" "$tpl2/template/.githooks" "$tpl2/template/.github/workflows"
(
  cd "$tpl2" && git init -q . && git config user.email t@t && git config user.name t
  mk() { # version label, "labels" when that version has the Labels section — the template at that version
    { printf '# {{ project_name }}\n\n## Feature milestones (ALWAYS)\n\nRule %s.\n\n' "$1"
      [ "${2:-}" != labels ] || printf '## Labels (ALWAYS)\n\nLabels %s.\n\n' "$1"
      printf '## Commits & PRs\n'; } > template/AGENTS.md.jinja
    printf '# {{ project_name }}\n' > template/CLAUDE.md.jinja
    printf 'name: linkage\n# %s\n' "$1" > template/.github/workflows/linkage.yml
    for f in scripts/check-linkage.sh scripts/check-linkage_test.sh .claude/hooks/linkage-guard.sh \
             .claude/hooks/linkage-guard_test.sh .githooks/pre-push .githooks/pre-push_test.sh; do
      printf '#!/usr/bin/env bash\n# %s %s\n' "$f" "$1" > "template/$f"
    done
  }
  mk one; git add -A; git commit -qm one; git tag v0.1.0
  mk two labels; git add -A; git commit -qm two; git tag v0.2.0
  mk three labels; git add -A; git commit -qm three
)
run2() { # adopt.sh arguments against the template that has history
  : > "$tmp/copier.log"
  out="$(PATH="$bin:$PATH" TEMPLATE_DIR="$tpl2/template" COPIER_LOG="$tmp/copier.log" bash "$script" "$@" 2>&1)"; rc=$?
}
gate_at() { # relative path, version label — the content a template of that version put there
  printf '#!/usr/bin/env bash\n# %s %s\n' "$1" "$2"
}

# R1. a gate file equal to an older released template is replaced, with the version named
new_repo refresh-old
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
write scripts/check-linkage.sh "$(gate_at scripts/check-linkage.sh one)"$'\n'
run2 --refresh "$repo"
check "refresh: a file equal to an old template is updated" $([ "$(cat "$repo/scripts/check-linkage.sh")" = "$(gate_at scripts/check-linkage.sh three)" ] && echo 0 || echo 1) "$(cat "$repo/scripts/check-linkage.sh")"
check "refresh: the report names the version it was" $(has 'updated: scripts/check-linkage.sh (was the template of v0.1.0)' && echo 0 || echo 1) "out=$out"

# R2. a gate file that equals no released template is kept
new_repo refresh-local
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
write scripts/check-linkage.sh $'#!/usr/bin/env bash\n# local variant\n'
run2 --refresh "$repo"
check "refresh: a local variant is kept" $([ "$(cat "$repo/scripts/check-linkage.sh")" = $'#!/usr/bin/env bash\n# local variant' ] && echo 0 || echo 1) "$(cat "$repo/scripts/check-linkage.sh")"
check "refresh: it is reported as a local variant" $(has 'kept: scripts/check-linkage.sh (differs from every released template)' && echo 0 || echo 1) "out=$out"

# R3. a file already equal to the current template is not touched
new_repo refresh-current
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
mkdir -p "$repo/scripts"; cp "$tpl2/template/scripts/check-linkage.sh" "$repo/scripts/check-linkage.sh"
run2 --refresh "$repo"
check "refresh: a current file is reported as the same" $(has 'kept: scripts/check-linkage.sh (same as the template)' && echo 0 || echo 1) "out=$out"

# R4. an old section is replaced by the current one, and nothing else of AGENTS.md changes
new_repo refresh-section
write AGENTS.md $'# Mine\n\nOur text.\n\n## Feature milestones (ALWAYS)\n\nRule one.\n\n## Commits & PRs\n\n- ours\n'
run2 --refresh "$repo"
check "refresh: an old section is replaced" $(grep -qF 'Rule three.' "$repo/AGENTS.md" && ! grep -qF 'Rule one.' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "refresh: the rest of AGENTS.md is untouched" $(grep -qF 'Our text.' "$repo/AGENTS.md" && grep -qF -- '- ours' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "refresh: the report says the section was updated" $(has 'updated: AGENTS.md (Feature milestones was the template of v0.1.0)' && echo 0 || echo 1) "out=$out"

# R5. a section the repository edited is kept and flagged
new_repo refresh-section-edited
write AGENTS.md $'# Mine\n\n## Feature milestones (ALWAYS)\n\nOur own wording.\n\n## Commits & PRs\n'
run2 --refresh "$repo"
check "refresh: an edited section is kept" $(grep -qF 'Our own wording.' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "refresh: it says to review it by hand" $(has 'kept: AGENTS.md (Feature milestones differs from every released template; review by hand)' && echo 0 || echo 1) "out=$out"

# R5b. an AGENTS.md refreshed from a release before Labels existed gets the section
new_repo refresh-labels-new
write AGENTS.md $'# Mine\n\n## Feature milestones (ALWAYS)\n\nRule one.\n\n## Commits & PRs\n'
run2 --refresh "$repo"
check "refresh: Labels is inserted after the refreshed Feature milestones" $(awk '/^Rule three\./{f=NR} /^Labels three\./{l=NR} /^## Commits & PRs/{c=NR} END{exit !(f && l && c && f < l && l < c)}' "$repo/AGENTS.md" && has 'inserted: AGENTS.md (Labels)' && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"

# R5c. an old Labels section is replaced by the current one, an edited one is kept
new_repo refresh-labels-old
write AGENTS.md $'# Mine\n\n## Feature milestones (ALWAYS)\n\nRule three.\n\n## Labels (ALWAYS)\n\nLabels two.\n\n## Commits & PRs\n\n- ours\n'
run2 --refresh "$repo"
check "refresh: an old Labels section is replaced" $(grep -qF 'Labels three.' "$repo/AGENTS.md" && ! grep -qF 'Labels two.' "$repo/AGENTS.md" && grep -qF -- '- ours' "$repo/AGENTS.md" && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "refresh: the report says Labels was updated" $(has 'updated: AGENTS.md (Labels was the template of v0.2.0)' && has 'kept: AGENTS.md (has Feature milestones)' && echo 0 || echo 1) "out=$out"
new_repo refresh-labels-edited
write AGENTS.md $'# Mine\n\n## Feature milestones (ALWAYS)\n\nRule three.\n\n## Labels (ALWAYS)\n\nOur labels.\n\n## Commits & PRs\n'
run2 --refresh "$repo"
check "refresh: an edited Labels section is kept and flagged" $(grep -qF 'Our labels.' "$repo/AGENTS.md" && has 'kept: AGENTS.md (Labels differs from every released template; review by hand)' && echo 0 || echo 1) "out=$out"

# R5d. a heading of the repository's own that only starts like the section is not taken for
#      the section of a release that had none
new_repo refresh-labels-own
own_labels=$'# Mine\n\n## Feature milestones (ALWAYS)\n\nRule three.\n\n## Labels we use\n\nOur list.\n\n## Commits & PRs\n'
write AGENTS.md "$own_labels"
run2 --refresh "$repo"
check "refresh: an own heading is not replaced" $([ "$(cat "$repo/AGENTS.md")" = "${own_labels%$'\n'}" ] && ! has 'updated: AGENTS.md' && echo 0 || echo 1) "out=$out
$(cat "$repo/AGENTS.md")"

# R6. without --refresh an old file is kept as before
new_repo refresh-off
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
write scripts/check-linkage.sh "$(gate_at scripts/check-linkage.sh one)"$'\n'
run2 "$repo"
check "refresh-off: no update without --refresh" $(has 'kept: scripts/check-linkage.sh (differs from the template)' && ! has 'updated:' && echo 0 || echo 1) "out=$out"

# R7. --dry-run with --refresh writes nothing
new_repo refresh-dry
write AGENTS.md $'# Mine\n\n## Feature milestones (ALWAYS)\n\nRule one.\n\n## Commits & PRs\n'
write scripts/check-linkage.sh "$(gate_at scripts/check-linkage.sh one)"$'\n'
before=$(snapshot)
run2 --dry-run --refresh "$repo"
check "refresh-dry: nothing is written" $([ "$(snapshot)" = "$before" ] && echo 0 || echo 1) "$(diff <(echo "$before") <(snapshot))"
check "refresh-dry: it still reports the update" $(has 'updated: scripts/check-linkage.sh' && echo 0 || echo 1) "out=$out"

# R8. --refresh needs the template's history
new_repo refresh-nogit
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
run --refresh "$repo"
check "refresh-nogit: a template without history is refused" $([ "$rc" -eq 2 ] && has 'history' && echo 0 || echo 1) "rc=$rc out=$out"

# W1. the PR check workflow is added when the repository has none
new_repo wf-add
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
run "$repo"
check "workflow: a repository without a PR check gets .github/workflows/linkage.yml" $([ -f "$repo/.github/workflows/linkage.yml" ] && has 'added: .github/workflows/linkage.yml' && echo 0 || echo 1) "out=$out"

# W2. a workflow of the repository that already runs the PR gate is enough
new_repo wf-existing
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
write .github/workflows/ci.yml $'name: ci\njobs:\n  linkage:\n    steps:\n      - run: bash scripts/check-linkage.sh --pr "$N"\n'
run "$repo"
check "workflow: an existing job that runs the PR gate is kept and no second workflow is added" $([ ! -e "$repo/.github/workflows/linkage.yml" ] && has 'kept: .github/workflows/ci.yml (already runs the PR gate)' && echo 0 || echo 1) "out=$out"

# W3. a workflow that only audits a release is not a PR check
new_repo wf-release-only
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
write .github/workflows/release.yml $'name: release\njobs:\n  guard:\n    steps:\n      - run: bash scripts/check-linkage.sh --for-tag "$TAG"\n'
run "$repo"
check "workflow: a release-only audit does not count as a PR check" $([ -f "$repo/.github/workflows/linkage.yml" ] && echo 0 || echo 1) "out=$out"

# W4. a linkage.yml the repository already has is kept, byte for byte
new_repo wf-own
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
write .github/workflows/linkage.yml $'name: linkage\n# mine\n'
run "$repo"
check "workflow: an existing linkage.yml is untouched" $([ "$(cat "$repo/.github/workflows/linkage.yml")" = $'name: linkage\n# mine' ] && has 'kept: .github/workflows/linkage.yml (differs from the template)' && echo 0 || echo 1) "out=$out"

# ---- --speckit: the Spec Kit kit of the template, byte for byte --------------------------
# A second fake template, with a kit: two skills, a script, the manifest, the constitution's
# starting point and the three files that go with the kit.
tplk="$tmp/template-kit"; rm -rf "$tplk"; cp -R "$tpl" "$tplk"
mkkit() { # path, content — a file of the fake kit
  mkdir -p "$(dirname "$tplk/$1")"; printf '%s' "$2" > "$tplk/$1"
}
mkkit .claude/skills/speckit-plan/SKILL.md $'plan skill v2\n'
mkkit .agents/skills/speckit-plan/SKILL.md $'plan skill for codex v2\n'
mkkit .specify/scripts/bash/common.sh $'#!/bin/sh\necho common\n'
mkkit .specify/extensions.yml $'hooks: {}\n'
mkkit .specify/memory/constitution.md $'# [PROJECT_NAME] Constitution\n'
mkkit .specify/memory/.constitution-template.json $'{"source": "core"}\n'
chmod +x "$tplk/.specify/scripts/bash/common.sh"
( cd "$tplk" && shasum -a 256 .claude/skills/speckit-plan/SKILL.md .agents/skills/speckit-plan/SKILL.md \
    .specify/scripts/bash/common.sh .specify/extensions.yml > .specify/speckit-kit.sha256 )
mkkit scripts/check-speckit.sh $'#!/usr/bin/env bash\n# check-speckit\n'
mkkit scripts/check-speckit_test.sh $'#!/usr/bin/env bash\n# check-speckit test\n'
mkkit .github/workflows/speckit.yml $'name: speckit\n'
run3() { # adopt.sh arguments against the template with a kit; sets $out and $rc
  out="$(PATH="$bin:$PATH" TEMPLATE_DIR="$tplk" COPIER_LOG="$tmp/copier.log" bash "$script" "$@" 2>&1)"; rc=$?
}
kit_ok() { # the kit of $repo is the fake template's
  ( cd "$repo" && shasum -a 256 -c .specify/speckit-kit.sha256 >/dev/null 2>&1 )
}

# K1. a repository without Spec Kit gets the kit, the manifest, the check and its workflow
new_repo kit-fresh
write AGENTS.md $'# Mine\n'
run3 --speckit "$repo"
check "kit-fresh: the run succeeds" $([ "$rc" -eq 0 ] && echo 0 || echo 1) "rc=$rc out=$out"
check "kit-fresh: both skills are there" $([ -f "$repo/.claude/skills/speckit-plan/SKILL.md" ] && [ -f "$repo/.agents/skills/speckit-plan/SKILL.md" ] && echo 0 || echo 1) "out=$out"
check "kit-fresh: every file of the manifest matches it" $(kit_ok && echo 0 || echo 1) "out=$out"
check "kit-fresh: a script keeps its executable bit" $([ -x "$repo/.specify/scripts/bash/common.sh" ] && echo 0 || echo 1) "out=$out"
check "kit-fresh: the check, its test and its workflow come with the kit" $([ -f "$repo/scripts/check-speckit.sh" ] && [ -f "$repo/scripts/check-speckit_test.sh" ] && [ -f "$repo/.github/workflows/speckit.yml" ] && echo 0 || echo 1) "out=$out"
check "kit-fresh: the constitution starts from the template's" $(grep -qF 'Constitution' "$repo/.specify/memory/constitution.md" && [ -f "$repo/.specify/memory/.constitution-template.json" ] && echo 0 || echo 1) "out=$out"
check "kit-fresh: nothing else of the usual run happens" $([ ! -e "$repo/CLAUDE.md" ] && [ ! -e "$repo/scripts/check-linkage.sh" ] && [ "$(cat "$repo/AGENTS.md")" = '# Mine' ] && echo 0 || echo 1) "out=$out"
check "kit-fresh: it counts what it added" $(has 'kit: ' && has 'added' && echo 0 || echo 1) "out=$out"

# K2. a repository with another Spec Kit's files: replaced, extras and CLI state removed, own things kept
new_repo kit-old
write AGENTS.md $'# Mine\n'
write .claude/skills/speckit-plan/SKILL.md $'plan skill v1, edited here\n'
write .claude/skills/speckit-old/SKILL.md $'a skill the template no longer has\n'
write .claude/skills/galaxio-own/SKILL.md $'the repository own skill\n'
write .specify/scripts/bash/mine.sh $'#!/bin/sh\n'
write .specify/extensions/.registry $'{}\n'
write .specify/extensions/.cache/catalog.json $'{}\n'
write .specify/extensions/.backup/old.yml $'x\n'
write .specify/presets/.registry $'{}\n'
write .specify/integrations/claude.manifest.json $'{}\n'
write .specify/workflows/workflow-registry.json $'{}\n'
write .specify/feature.json $'{"feature_directory": "specs/001-x"}\n'
write .specify/memory/constitution.md $'# Our own constitution\n\nWritten here.\n'
write setup-speckit.sh $'#!/usr/bin/env bash\n'
run3 --speckit "$repo"
check "kit-old: the run succeeds" $([ "$rc" -eq 0 ] && echo 0 || echo 1) "rc=$rc out=$out"
check "kit-old: the edited skill is the template's again" $([ "$(cat "$repo/.claude/skills/speckit-plan/SKILL.md")" = 'plan skill v2' ] && has 'updated: .claude/skills/speckit-plan/SKILL.md' && echo 0 || echo 1) "out=$out"
check "kit-old: every file of the manifest matches it" $(kit_ok && echo 0 || echo 1) "out=$out"
check "kit-old: a skill and a script the template does not have are removed" $([ ! -e "$repo/.claude/skills/speckit-old" ] && [ ! -e "$repo/.specify/scripts/bash/mine.sh" ] && has 'removed: .claude/skills/speckit-old/SKILL.md' && echo 0 || echo 1) "out=$out"
check "kit-old: the CLI's state is removed" $([ ! -e "$repo/.specify/extensions/.registry" ] && [ ! -e "$repo/.specify/extensions/.cache" ] && [ ! -e "$repo/.specify/extensions/.backup" ] && [ ! -e "$repo/.specify/presets/.registry" ] && [ ! -e "$repo/.specify/integrations/claude.manifest.json" ] && [ ! -e "$repo/.specify/workflows/workflow-registry.json" ] && echo 0 || echo 1) "$(cd "$repo" && find .specify -type f | sort)"
check "kit-old: a skill that is not a speckit-* one is kept" $([ -f "$repo/.claude/skills/galaxio-own/SKILL.md" ] && echo 0 || echo 1) "out=$out"
check "kit-old: the constitution and feature.json are untouched" $([ "$(cat "$repo/.specify/memory/constitution.md")" = $'# Our own constitution\n\nWritten here.' ] && [ -f "$repo/.specify/feature.json" ] && echo 0 || echo 1) "out=$out"
check "kit-old: the constitution's marker is added when missing" $([ -f "$repo/.specify/memory/.constitution-template.json" ] && echo 0 || echo 1) "out=$out"
check "kit-old: setup-speckit.sh is reported as obsolete and left" $([ -f "$repo/setup-speckit.sh" ] && has 'setup-speckit.sh' && has 'obsolete' && echo 0 || echo 1) "out=$out"

# K3. running it again changes nothing
before=$(snapshot)
run3 --speckit "$repo"
check "kit-again: nothing changes" $([ "$(snapshot)" = "$before" ] && echo 0 || echo 1) "$(diff <(echo "$before") <(snapshot))"
check "kit-again: it says so" $(has '0 added, 0 updated, 0 removed' && echo 0 || echo 1) "out=$out"

# K4. --dry-run writes nothing but says what it would do
new_repo kit-dry
write AGENTS.md $'# Mine\n'
write .claude/skills/speckit-plan/SKILL.md $'old\n'
write .claude/skills/speckit-old/SKILL.md $'old\n'
before=$(snapshot)
run3 --dry-run --speckit "$repo"
check "kit-dry: nothing is written" $([ "$(snapshot)" = "$before" ] && echo 0 || echo 1) "$(diff <(echo "$before") <(snapshot))"
check "kit-dry: it reports the update and the removal" $(has 'updated: .claude/skills/speckit-plan/SKILL.md' && has 'removed: .claude/skills/speckit-old/SKILL.md' && echo 0 || echo 1) "out=$out"

# K5. a template without a kit is refused
new_repo kit-none
write AGENTS.md $'# Mine\n'
run --speckit "$repo"
check "kit-none: a template without a manifest is refused" $([ "$rc" -eq 2 ] && has 'build-speckit-kit.sh' && echo 0 || echo 1) "rc=$rc out=$out"

# K6. without --speckit the kit is not touched
new_repo kit-off
write AGENTS.md $'# Mine\n\n## Commits & PRs\n'
write .claude/skills/speckit-plan/SKILL.md $'mine\n'
run3 "$repo"
check "kit-off: the usual run leaves the kit alone" $([ "$(cat "$repo/.claude/skills/speckit-plan/SKILL.md")" = 'mine' ] && [ ! -e "$repo/.specify/speckit-kit.sha256" ] && echo 0 || echo 1) "out=$out"

# K7. skills that are dangling symlinks (an extension's dev directory) are replaced by the files
new_repo kit-symlink
write AGENTS.md $'# Mine\n'
mkdir -p "$repo/.claude/skills/speckit-plan" "$repo/.claude/skills/speckit-link"
ln -s ../../../.specify/extensions/gone/SKILL.md "$repo/.claude/skills/speckit-plan/SKILL.md"
ln -s ../../../.specify/extensions/gone/SKILL.md "$repo/.claude/skills/speckit-link/SKILL.md"
run3 --speckit "$repo"
check "kit-symlink: the run succeeds" $([ "$rc" -eq 0 ] && echo 0 || echo 1) "rc=$rc out=$out"
check "kit-symlink: a dangling link is replaced by the template's file" $([ ! -L "$repo/.claude/skills/speckit-plan/SKILL.md" ] && [ "$(cat "$repo/.claude/skills/speckit-plan/SKILL.md")" = 'plan skill v2' ] && echo 0 || echo 1) "out=$out"
check "kit-symlink: a link the template does not have is removed" $([ ! -e "$repo/.claude/skills/speckit-link" ] && [ ! -L "$repo/.claude/skills/speckit-link/SKILL.md" ] && echo 0 || echo 1) "out=$out"
check "kit-symlink: every file of the manifest matches it" $(kit_ok && echo 0 || echo 1) "out=$out"

# K8. .gitignore: the lines the kit needs are added, once, and the rest of the file is kept
new_repo kit-ignore
write AGENTS.md $'# Mine\n'
write .gitignore $'target/\n__pycache__/\n.idea/\n'
run3 --speckit "$repo"
check "kit-ignore: the CLI's state and __pycache__ are ignored" $(grep -qxF '.specify/extensions/.registry' "$repo/.gitignore" && grep -qxF '.specify/integrations/*.manifest.json' "$repo/.gitignore" && echo 0 || echo 1) "$(cat "$repo/.gitignore")"
check "kit-ignore: a line that was there is not repeated and the others are kept" $([ "$(grep -cxF '__pycache__/' "$repo/.gitignore")" = 1 ] && grep -qxF 'target/' "$repo/.gitignore" && grep -qxF '.idea/' "$repo/.gitignore" && echo 0 || echo 1) "$(cat "$repo/.gitignore")"
before=$(snapshot); run3 --speckit "$repo"
check "kit-ignore: a second run adds nothing" $([ "$(snapshot)" = "$before" ] && echo 0 || echo 1) "$(cat "$repo/.gitignore")"
new_repo kit-ignore-none
write AGENTS.md $'# Mine\n'
run3 --speckit "$repo"
check "kit-ignore: a repository without .gitignore gets one" $(grep -qxF '.specify/presets/.registry' "$repo/.gitignore" && echo 0 || echo 1) "out=$out"
new_repo kit-ignore-dry
write AGENTS.md $'# Mine\n'
run3 --dry-run --speckit "$repo"
check "kit-ignore: --dry-run writes no .gitignore" $([ ! -e "$repo/.gitignore" ] && has '.gitignore' && echo 0 || echo 1) "out=$out"

# K9. --overlay: a layer's skills go over the kit's, with their manifest; --speckit alone takes them away
lay="$tmp/layers/over"; rm -rf "$lay"; mkdir -p "$lay/.claude/skills/speckit-plan" "$lay/.agents/skills/speckit-plan" "$lay/.specify"
printf 'plan skill with a layer\n' > "$lay/.claude/skills/speckit-plan/SKILL.md"
printf 'plan skill for codex with a layer\n' > "$lay/.agents/skills/speckit-plan/SKILL.md"
( cd "$lay" && shasum -a 256 .agents/skills/speckit-plan/SKILL.md .claude/skills/speckit-plan/SKILL.md > .specify/speckit-overlay.sha256 )
new_repo layer-fresh
write AGENTS.md $'# Mine\n'
run3 --speckit --overlay over "$repo"
check "layer: the run succeeds" $([ "$rc" -eq 0 ] && echo 0 || echo 1) "rc=$rc out=$out"
check "layer: the layer's skills are there, for both integrations" $([ "$(cat "$repo/.claude/skills/speckit-plan/SKILL.md")" = 'plan skill with a layer' ] && [ "$(cat "$repo/.agents/skills/speckit-plan/SKILL.md")" = 'plan skill for codex with a layer' ] && echo 0 || echo 1) "out=$out"
check "layer: the rest of the kit is the template's" $([ "$(cat "$repo/.specify/extensions.yml")" = 'hooks: {}' ] && echo 0 || echo 1) "out=$out"
check "layer: the overlay manifest is there" $(cmp -s "$lay/.specify/speckit-overlay.sha256" "$repo/.specify/speckit-overlay.sha256" && echo 0 || echo 1) "out=$out"
check "layer: a layer file is counted once, as added" $(grep -q '^kit: 11 added, 0 updated' <<<"$out" && echo 0 || echo 1) "out=$out"
before=$(snapshot); run3 --speckit --overlay over "$repo"
check "layer: a second run changes nothing" $([ "$(snapshot)" = "$before" ] && grep -q '0 added, 0 updated, 0 removed' <<<"$out" && echo 0 || echo 1) "out=$out"
write .claude/skills/speckit-plan/SKILL.md $'edited here\n'
run3 --speckit --overlay over "$repo"
check "layer: an edited layer file is the layer's again" $([ "$(cat "$repo/.claude/skills/speckit-plan/SKILL.md")" = 'plan skill with a layer' ] && has 'updated: .claude/skills/speckit-plan/SKILL.md' && echo 0 || echo 1) "out=$out"
run3 --speckit "$repo"
check "layer: --speckit alone gives the kit back and removes the manifest" $([ "$(cat "$repo/.claude/skills/speckit-plan/SKILL.md")" = 'plan skill v2' ] && [ ! -e "$repo/.specify/speckit-overlay.sha256" ] && has 'removed: .specify/speckit-overlay.sha256' && echo 0 || echo 1) "out=$out"
new_repo layer-dry
write AGENTS.md $'# Mine\n'
run3 --dry-run --speckit --overlay over "$repo"
check "layer: --dry-run writes nothing" $([ ! -e "$repo/.specify" ] && [ ! -e "$repo/.claude" ] && echo 0 || echo 1) "out=$out"
run3 --overlay over "$repo"
check "layer: --overlay without --speckit is refused" $([ "$rc" -eq 2 ] && has 'goes with --speckit' && echo 0 || echo 1) "rc=$rc out=$out"
run3 --speckit --overlay nosuch "$repo"
check "layer: an unknown layer is refused" $([ "$rc" -eq 2 ] && has 'no layer' && echo 0 || echo 1) "rc=$rc out=$out"
mkdir -p "$tmp/layers/stray/.specify"; printf '%s  %s\n' "$(printf x | shasum -a 256 | cut -d' ' -f1)" .claude/skills/speckit-new/SKILL.md > "$tmp/layers/stray/.specify/speckit-overlay.sha256"
run3 --speckit --overlay stray "$repo"
check "layer: a layer that replaces a file the kit lacks is refused" $([ "$rc" -eq 2 ] && has 'does not have' && echo 0 || echo 1) "rc=$rc out=$out"
run3 --speckit --overlay '../x' "$repo"
check "layer: a name that is a path is refused" $([ "$rc" -eq 2 ] && echo 0 || echo 1) "rc=$rc out=$out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
