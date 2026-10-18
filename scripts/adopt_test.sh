#!/usr/bin/env bash
#
# adopt_test.sh — tests for scripts/adopt.sh.
#
# Hermetic: TEMPLATE_DIR points at a tiny fake template, and a stub `copier` on PATH
# renders the two files the script asks it for. What is under test is the promise of
# adopt.sh: it brings the process into a repository that was not made from the
# template WITHOUT replacing anything the repository already has — a file that exists
# is kept byte for byte, the Feature milestones section is inserted into an existing
# AGENTS.md and nothing else of it changes, files that are missing are added, and
# running it twice changes nothing.

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

# 2. an AGENTS.md that already has the section is left alone
new_repo has-section
write AGENTS.md $'# Mine\n\n## Feature milestones (ALWAYS)\n\nOur edited version.\n\n## Commits & PRs\n'
before=$(snapshot)
run "$repo"
check "has-section: AGENTS.md is not changed" $([ "$(snapshot | grep AGENTS.md)" = "$(grep AGENTS.md <<<"$before")" ] && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
check "has-section: it says the section is there" $(has 'kept: AGENTS.md (has Feature milestones)' && echo 0 || echo 1) "out=$out"

# 3. no "Commits & PRs" heading: the section is appended
new_repo append
write AGENTS.md $'# Mine\n\nOnly this.\n'
run "$repo"
check "append: the section is added at the end" $(tail -n 8 "$repo/AGENTS.md" | grep -q '^## Feature milestones' && echo 0 || echo 1) "$(cat "$repo/AGENTS.md")"
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
check "dry-run: it still reports what it would do" $(has 'inserted: AGENTS.md (Feature milestones)' && has 'added: scripts/check-linkage.sh' && echo 0 || echo 1) "out=$out"
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
  mk() { # version label — the template at that version
    printf '# {{ project_name }}\n\n## Feature milestones (ALWAYS)\n\nRule %s.\n\n## Commits & PRs\n' "$1" > template/AGENTS.md.jinja
    printf '# {{ project_name }}\n' > template/CLAUDE.md.jinja
    printf 'name: linkage\n# %s\n' "$1" > template/.github/workflows/linkage.yml
    for f in scripts/check-linkage.sh scripts/check-linkage_test.sh .claude/hooks/linkage-guard.sh \
             .claude/hooks/linkage-guard_test.sh .githooks/pre-push .githooks/pre-push_test.sh; do
      printf '#!/usr/bin/env bash\n# %s %s\n' "$f" "$1" > "template/$f"
    done
  }
  mk one; git add -A; git commit -qm one; git tag v0.1.0
  mk two; git add -A; git commit -qm two; git tag v0.2.0
  mk three; git add -A; git commit -qm three
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
