#!/usr/bin/env bash
#
# kit-templates_test.sh — tests for how the kit's scripts resolve their templates.
#
# speckit-specify, speckit-constitution, setup-plan.sh and setup-tasks.sh get a template from the resolver in
# .specify/scripts/bash/common.sh, and stop when it fails. The resolver needs Python 3 with PyYAML as soon as
# the kit holds the manifest of a preset, which a machine or a sandbox that runs the kit need not have
# (BCKLG-1067). So the kit holds none, and every template resolves to its file with no Python at all.
#
# Hermetic: the kit of template/ (or KIT_TEMPLATE) is copied to a fresh directory, and `python3`, `python` and
# `py` on PATH are stand-ins that fail, so no Python and no PyYAML of the host is used. No network.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
kit="${KIT_TEMPLATE:-$root/template}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset SPECIFY_INIT_DIR SPECIFY_FEATURE SPECIFY_FEATURE_DIRECTORY SPECKIT_PYTHON_EXECUTABLE SPECKIT_PYTHON

pass=0; fail=0
ok()  { printf '  ✓ %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  ✗ %s\n     %s\n' "$1" "$2"; fail=$((fail + 1)); }
check() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "$3"; fi; }

mkdir -p "$tmp/nopython" "$tmp/repo/specs/001-probe"
for p in python3 python py; do printf '#!/bin/sh\nexit 127\n' > "$tmp/nopython/$p"; chmod +x "$tmp/nopython/$p"; done
cp -R "$kit/.specify" "$tmp/repo/.specify"
git -C "$tmp/repo" init -q
run() { ( cd "$tmp/repo" && PATH="$tmp/nopython:$PATH" "$@" ) >"$tmp/out" 2>"$tmp/err"; }

echo "the kit's templates resolve with no Python"
manifests="$(cd "$kit" && find .specify -path '.specify/presets/*' -name preset.yml)"
[ -z "$manifests" ]; check "the kit holds no preset manifest" $? "$manifests"

count=0
for file in "$kit"/.specify/templates/*-template.md; do
  name="$(basename "$file" .md)"; count=$((count + 1))
  run bash .specify/scripts/bash/resolve-template.sh "$name" && cmp -s "$tmp/out" "$file"
  check "$name resolves to its file" $? "$(cat "$tmp/err")"
done
[ "$count" -ge 5 ]; check "the spec, plan, tasks, checklist and constitution templates were tried" $? "found $count"

export SPECIFY_FEATURE_DIRECTORY=specs/001-probe
printf '# Spec\n' > "$tmp/repo/specs/001-probe/spec.md"
run bash .specify/scripts/bash/setup-plan.sh --json && cmp -s "$tmp/repo/specs/001-probe/plan.md" "$kit/.specify/templates/plan-template.md"
check "setup-plan.sh writes plan.md from the plan template" $? "$(cat "$tmp/err")"
run bash .specify/scripts/bash/setup-tasks.sh --json && grep -q '"TASKS_TEMPLATE_CONTENT":".*# Tasks: \[FEATURE NAME\]' "$tmp/out"
check "setup-tasks.sh gives the tasks template" $? "$(cat "$tmp/err"; head -c 300 "$tmp/out")"

echo "clarify and checklist are in both skill sets, on the deep tier for Claude Code"
for c in clarify checklist; do
  [ -f "$kit/.claude/skills/speckit-$c/SKILL.md" ] && [ -f "$kit/.agents/skills/speckit-$c/SKILL.md" ]
  check "speckit-$c is there for Claude Code and Codex" $? ""
  grep -qx 'model: opus' "$kit/.claude/skills/speckit-$c/SKILL.md"; check "speckit-$c keeps its model pin" $? ""
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
