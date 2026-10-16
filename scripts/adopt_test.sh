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
mkdir -p "$tpl/scripts" "$tpl/.claude/hooks" "$tpl/.githooks"
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
