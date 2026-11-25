#!/usr/bin/env bash
#
# hooks-off_test.sh — tests for the kit's hook scripts under SPECKIT_HOOKS=off.
#
# TEMPORARY: removed with the guard by galax-io/galaxio-sdlc-backlog#1043.
#
# The kit is the same in every repository, and a person runs its git, worktree and agent-context hooks by
# hand. An automated run (the engine's, whose sandbox adapter sets SPECKIT_HOOKS=off) must not: the run
# keeps its own branch, commits and working copy. So each script a hook runs changes nothing and exits 0
# when SPECKIT_HOOKS=off, and is untouched otherwise. setup-speckit.sh adds the guard after the install;
# this suite checks the kit it built, template/ (or KIT_TEMPLATE, to show the suite fails on an unguarded kit).
#
# Hermetic: each script runs in a fresh directory of its own, with no git config of the host, no network.
# Each script gets the arguments and the state under which, unguarded, it would change the repository.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
kit="${KIT_TEMPLATE:-$root/template}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset SPECIFY_INIT_DIR GIT_BRANCH_NAME SPECIFY_FEATURE SPECIFY_FEATURE_DIRECTORY

pass=0; fail=0
ok()  { printf '  ✓ %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  ✗ %s\n     %s\n' "$1" "$2"; fail=$((fail + 1)); }
check() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "$3"; fi; }

# A directory with the kit, a file to commit and a plan; a git repository with one commit unless told "bare".
fixture() {
  local dir="$tmp/$1"
  mkdir -p "$dir/specs/001-probe"
  cp -R "$kit/.specify" "$dir/.specify"
  printf 'work\n' > "$dir/file.txt"
  printf '# Plan\n\n**Language/Version**: Bash 5\n' > "$dir/specs/001-probe/plan.md"
  if [ "${2:-}" != bare ]; then
    git -C "$dir" init -q -b main && git -C "$dir" commit -q --allow-empty -m base \
      || { echo "fixture: git failed in $dir" >&2; exit 2; }
  fi
  echo "$dir"
}
state() { # what a hook could change: the .git directory, branches, commits, worktrees, the files
  if [ -d "$1/.git" ]; then
    git -C "$1" for-each-ref --format='%(refname)' refs/heads; git -C "$1" rev-list --all; git -C "$1" worktree list --porcelain
  else
    echo 'no repository'
  fi
  (cd "$1" && find . -path ./.git -prune -o -type f -print | sort | xargs cksum)
}

# hook script | how it is called | the fixture: "git", "bare" (no repository) or "commit" (auto-commit on)
CASES=(
  "git/scripts/bash/create-new-feature-branch.sh|--json --short-name probe probe-feature|git"
  "git/scripts/bash/auto-commit.sh|after_specify probe|commit"
  "git/scripts/bash/initialize-repo.sh||bare"
  "worktrees/scripts/bash/create-worktree.sh|--json 001-probe|git"
  "agent-context/scripts/bash/update-agent-context.sh|specs/001-probe/plan.md|git"
)

echo "a hook script changes nothing under SPECKIT_HOOKS=off"
for case in "${CASES[@]}"; do
  IFS='|' read -r hook args kind <<< "$case"
  name="$(basename "$hook" .sh)"
  dir="$(fixture "$name" "$kind")"
  if [ "$kind" = commit ]; then
    config="$dir/.specify/extensions/git/git-config.yml"
    sed -e 's/^  default: false$/  default: true/' -e 's/^    enabled: false$/    enabled: true/' "$config" > "$config.new" && mv "$config.new" "$config"
  fi
  before="$(state "$dir")"
  # shellcheck disable=SC2086 # the arguments of a case are words
  out="$(cd "$dir" && SPECKIT_HOOKS=off "./.specify/extensions/$hook" $args 2>&1)"; rc=$?
  check "$name exits 0" "$rc" "$out"
  after="$(state "$dir")"
  if [ "$after" = "$before" ]; then rc=0; else rc=1; fi
  check "$name leaves the repository and its files as they were" "$rc" "$(diff <(echo "$before") <(echo "$after"))"
  printf '%s' "$out" | grep -q 'SPECKIT_HOOKS=off'; check "$name says it was skipped and why" $? "$out"
done

echo "each script is guarded on its first line after the shebang, and stays executable"
for case in "${CASES[@]}"; do
  hook="${case%%|*}"; file="$kit/.specify/extensions/$hook"; name="$(basename "$hook")"
  [ -f "$file" ] || { bad "$hook exists" "missing $file"; continue; }
  if [ -x "$file" ]; then rc=0; else rc=1; fi
  check "$name is executable" "$rc" "$(ls -l "$file")"
  second="$(sed -n 2p "$file")"
  printf '%s' "$second" | grep -q 'SPECKIT_HOOKS'; check "$name is guarded on line 2" $? "$second"
  uses="$(grep -c 'SPECKIT_HOOKS' "$file")"
  if [ "$uses" -eq 1 ]; then rc=0; else rc=1; fi
  check "$name reads SPECKIT_HOOKS only in the guard" "$rc" "$(grep -n 'SPECKIT_HOOKS' "$file")"
done

echo "the worktree hook runs its script, which the guard stops, by a path that exists"
for skill in .specify/extensions/worktrees/commands/speckit.worktrees.create.md .claude/skills/speckit-worktrees-create/SKILL.md .agents/skills/speckit-worktrees-create/SKILL.md; do
  # shellcheck disable=SC2016 # the text searched for is literal
  ! grep -q 'dirname "$0")/../scripts' "$kit/$skill"; check "$skill names no path relative to \$0" $? "$(grep -n 'dirname' "$kit/$skill")"
  grep -q 'bash \.specify/extensions/worktrees/scripts/bash/create-worktree\.sh' "$kit/$skill"; check "$skill runs .specify/extensions/worktrees/scripts/bash/create-worktree.sh" $? ""
done

echo "without SPECKIT_HOOKS a hook works as before"
dir="$(fixture plain)"
(cd "$dir" && env -u SPECKIT_HOOKS ./.specify/extensions/git/scripts/bash/create-new-feature-branch.sh --json --short-name probe probe-feature >/dev/null 2>&1)
git -C "$dir" for-each-ref --format='%(refname:short)' refs/heads | grep -qv '^main$'; check "create-new-feature-branch.sh still makes the feature branch" $? "$(git -C "$dir" branch)"

echo
echo "hooks-off: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
