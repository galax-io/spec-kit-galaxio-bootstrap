#!/usr/bin/env bash
#
# check-linkage-template-repo_test.sh — the suite of check-linkage.sh, which the template and adopt.sh ship
# to every repository, passes in a repository that has a copier.yml of its own (a Copier template of the
# organization that adopted the process) but is not spec-kit-galaxio-bootstrap: the checks of its section 41
# (FR-008, FR-009) are the bootstrap's own and must not run there.

set -uo pipefail

name="check-linkage_test.sh: a repository with a copier.yml of its own does not run the bootstrap-only FR-008 and FR-009 checks"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail() { printf 'FAIL: %s\n  %s\n' "$name" "$1"; exit 1; }
real_mktemp="$(command -v mktemp)" || fail "mktemp not found"
tmp="$("$real_mktemp" -d "${TMPDIR:-/tmp}/check-linkage-tpl.XXXXXX")" || fail "no temporary directory"
trap 'rm -rf "$tmp"' EXIT

# A Copier template repository that adopted the process: its own copier.yml and AGENTS.md, the gate script
# and its suite, and none of the bootstrap's template/ files.
repo="$tmp/repo"; mkdir -p "$repo/scripts" "$tmp/bin"
cp "$here/check-linkage.sh" "$here/check-linkage_test.sh" "$repo/scripts/" || fail "cannot copy the suite"
cp "$here/../AGENTS.md" "$repo/AGENTS.md" || fail "cannot copy AGENTS.md"
printf 'project_name:\n  type: str\n  help: the name of the project\n' > "$repo/copier.yml"

# The suite's own mktemp -d (no template) lands in this case's directory: a sandbox may refuse the default.
cat > "$tmp/bin/mktemp" <<EOF
#!/bin/sh
if [ "\$#" -eq 1 ] && [ "\$1" = -d ]; then exec "$real_mktemp" -d "$tmp/suite.XXXXXX"; fi
exec "$real_mktemp" "\$@"
EOF
chmod +x "$tmp/bin/mktemp"

out="$(PATH="$tmp/bin:$PATH" bash "$repo/scripts/check-linkage_test.sh" 2>&1)"
summary=$(grep -E '^[0-9]+ passed, [0-9]+ failed$' <<<"$out")
[ -n "$summary" ] || fail "the suite did not finish: $(tail -n 20 <<<"$out")"
bad=$(grep -E '✗ FR-00[89]:' <<<"$out")
if [ -z "$bad" ]; then printf 'PASS: %s\n' "$name"; exit 0; fi
printf 'FAIL: %s\n%s\n' "$name" "$bad"; exit 1
