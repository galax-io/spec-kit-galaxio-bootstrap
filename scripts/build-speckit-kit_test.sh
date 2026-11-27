#!/usr/bin/env bash
#
# build-speckit-kit_test.sh — tests for scripts/build-speckit-kit.sh.
#
# Hermetic: no CLI, no network. The build runs on a checkout of its own with a stand-in for `specify` on
# PATH and a setup-speckit.sh that lays a few files, none of them executable, as a step of an install may
# leave them (Spec Kit 1.2.2 did, when it switched integrations). What is under test is the mode of the kit's
# scripts: the skills run them by their path, so every shell script a Spec Kit install makes executable is
# executable in the template, and --check fails when git holds one otherwise (BCKLG-1067).

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/build-speckit-kit.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset TEMPLATE_DIR

pass=0; fail=0
ok()  { printf '  ✓ %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  ✗ %s\n     %s\n' "$1" "$2"; fail=$((fail + 1)); }
check() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "$3"; fi; }

up="$tmp/up"; t="$up/template"; mkdir -p "$up/scripts" "$up/bin"
cp "$script" "$up/scripts/"
printf '#!/usr/bin/env bash\necho "CLI Version %s"\n' "$(sed -n 's/^KIT_VERSION=//p' "$script")" > "$up/bin/specify"
chmod +x "$up/bin/specify"
cat > "$up/setup-speckit.sh" <<'EOF'
#!/usr/bin/env bash
lay() { mkdir -p "$(dirname "$1")"; printf '%b' "$2" > "$1"; }
lay .claude/skills/speckit-plan/SKILL.md 'plan\n'
lay .agents/skills/speckit-plan/SKILL.md 'plan\n'
lay .specify/scripts/bash/setup-plan.sh '#!/usr/bin/env bash\n'
lay .specify/extensions/git/scripts/bash/auto-commit.sh '#!/usr/bin/env bash\n'
lay .specify/scripts/bash/no-shebang.sh 'echo sourced\n'
lay .specify/scripts/powershell/setup-plan.ps1 '#!/usr/bin/env pwsh\n'
EOF
git -C "$up" init -q && git -C "$up" config core.filemode true

build() { PATH="$up/bin:$PATH" bash "$up/scripts/build-speckit-kit.sh" "$@" >"$tmp/out" 2>&1; }
mode() { git -C "$t" ls-files -s -- "$1" | cut -d' ' -f1; }
scripts=(.specify/scripts/bash/setup-plan.sh .specify/extensions/git/scripts/bash/auto-commit.sh)
others=(.specify/scripts/bash/no-shebang.sh .specify/scripts/powershell/setup-plan.ps1 .claude/skills/speckit-plan/SKILL.md)

echo "build-speckit-kit.sh: the executable bit of the kit's scripts"
build; check "the build succeeds" $? "$(cat "$tmp/out")"
for s in "${scripts[@]}"; do
  [ -x "$t/$s" ]; check "the build makes $s executable" $? "$(ls -l "$t/$s" 2>&1)"
done
for f in "${others[@]}"; do
  [ -f "$t/$f" ] && [ ! -x "$t/$f" ]; check "and leaves $f as it was laid" $? "$(ls -l "$t/$f" 2>&1)"
done

git -C "$up" add -A
build --check; check "--check passes when git holds the scripts as 100755" $? "$(cat "$tmp/out")"

for s in "${scripts[@]}"; do
  git -C "$t" update-index --chmod=-x -- "$s"
  build --check; rc=$?
  [ "$rc" -eq 1 ] && grep -F -- "$s" "$tmp/out" | grep -q '100644 in git'; check "--check fails when git holds $s as 100644, though the file is executable" $? "rc=$rc: $(cat "$tmp/out")"
  grep -qF -- "update-index --add --chmod=+x $s" "$tmp/out"; check "  and says how to record the mode" $? "$(cat "$tmp/out")"
  git -C "$t" update-index --chmod=+x -- "$s"
done

s="${scripts[0]}"
chmod -x "$t/$s"; git -C "$t" update-index --chmod=-x -- "$s"
build --check; rc=$?
[ "$rc" -eq 1 ] && grep -qF -- "$s" "$tmp/out"; check "--check fails on a template where a script lost its bit" $? "rc=$rc: $(cat "$tmp/out")"
build; git -C "$up" add -A
[ "$(mode "$s")" = 100755 ]; check "a new build and git add record 100755 again" $? "mode=$(mode "$s")"

git -C "$t" rm -q --cached -- "$s"
build --check; rc=$?
[ "$rc" -eq 1 ] && grep -F -- "$s" "$tmp/out" | grep -q 'not in git'; check "--check fails on a script git does not hold" $? "rc=$rc: $(cat "$tmp/out")"
git -C "$up" add -A

cp -R "$t" "$tmp/plain"
TEMPLATE_DIR="$tmp/plain" build --check; rc=$?
[ "$rc" -eq 2 ] && grep -q 'not in a git work tree' "$tmp/out"; check "--check on a template outside git is an error, not a pass" $? "rc=$rc: $(cat "$tmp/out")"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
