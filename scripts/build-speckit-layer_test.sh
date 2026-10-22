#!/usr/bin/env bash
#
# build-speckit-layer_test.sh — tests for scripts/build-speckit-layer.sh and the preset text.
#
# Hermetic: no CLI. The composition (--compose) is run on small files. What is under test is the
# promise of the layer: the kit's frontmatter (and so its model pin) and the kit's whole command
# are kept, the preset's text is before and after it, and anything else fails the build. The preset's
# text is checked for the steps of spec 296 (galaxio-sdlc-backlog), since no suite can run an agent.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
script="$here/build-speckit-layer.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { printf '  ✓ %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  ✗ %s\n     %s\n' "$1" "$2"; fail=$((fail + 1)); }
check() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "$3"; fi; }

printf -- '---\nname: "speckit-specify"\nmodel: opus\n---\n\n## User Input\n\nDo the thing.\n' > "$tmp/kit.md"
printf '## Before you specify\n\nsteps\n\n{CORE_TEMPLATE}\n\n## After you specify\n\nchecks\n' > "$tmp/preset.md"
good() { printf -- '---\nname: other\n---\n\n# Skill\n\n## Before you specify\n\nsteps\n\n## User Input\n\nDo the thing.\n\n## After you specify\n\nchecks\n'; }

echo "compose"
good > "$tmp/cli.md"
bash "$script" --compose "$tmp/kit.md" "$tmp/cli.md" "$tmp/out.md" "$tmp/preset.md" 2>"$tmp/err"; check "a CLI skill that holds the kit's command whole composes" $? "$(cat "$tmp/err")"
grep -q '^model: opus$' "$tmp/out.md" && grep -q '^name: "speckit-specify"$' "$tmp/out.md"; check "the kit's frontmatter and model pin are kept, not the CLI's" $? "$(cat "$tmp/out.md")"
! grep -q 'name: other' "$tmp/out.md"; check "the CLI's frontmatter is dropped" $? ""
awk '/^## User Input/,/^## After/' "$tmp/out.md" | grep -q 'Do the thing.'; check "the kit's command is inside the result" $? ""
bash "$script" --compose "$tmp/kit.md" "$tmp/cli.md" "$tmp/out2.md" "$tmp/preset.md" 2>/dev/null; cmp -s "$tmp/out.md" "$tmp/out2.md"; check "composing twice gives the same file" $? ""

good | sed 's/^checks$/checks and something else/' > "$tmp/extra-after.md"
bash "$script" --compose "$tmp/kit.md" "$tmp/extra-after.md" "$tmp/o" "$tmp/preset.md" 2>"$tmp/err"; [ $? -ne 0 ] && grep -q 'after the kit.s command is not the preset' "$tmp/err"; check "text after the command that is not the preset's fails" $? "$(cat "$tmp/err")"
good | sed 's/^steps$/other steps/' > "$tmp/other-before.md"
bash "$script" --compose "$tmp/kit.md" "$tmp/other-before.md" "$tmp/o" "$tmp/preset.md" 2>"$tmp/err"; [ $? -ne 0 ] && grep -q 'before the kit.s command is not the preset' "$tmp/err"; check "text before the command that is not the preset's fails" $? "$(cat "$tmp/err")"
good | sed 's/Do the thing\./Do another thing./' > "$tmp/changed.md"
bash "$script" --compose "$tmp/kit.md" "$tmp/changed.md" "$tmp/o" "$tmp/preset.md" 2>"$tmp/err"; [ $? -ne 0 ] && grep -q 'does not hold the kit' "$tmp/err"; check "a CLI skill that changed the kit's command fails" $? "$(cat "$tmp/err")"
good | sed '/^## Before you specify/,/^steps/d' > "$tmp/nobefore.md"
bash "$script" --compose "$tmp/kit.md" "$tmp/nobefore.md" "$tmp/o" "$tmp/preset.md" 2>"$tmp/err"; [ $? -ne 0 ] && grep -q 'not before' "$tmp/err"; check "no preset text before the command fails" $? "$(cat "$tmp/err")"
good | sed '/^## After you specify/,$d' > "$tmp/noafter.md"
bash "$script" --compose "$tmp/kit.md" "$tmp/noafter.md" "$tmp/o" "$tmp/preset.md" 2>"$tmp/err"; [ $? -ne 0 ] && grep -q 'not after' "$tmp/err"; check "no preset text after the command fails" $? "$(cat "$tmp/err")"
printf 'no frontmatter\n' > "$tmp/nofm.md"
bash "$script" --compose "$tmp/nofm.md" "$tmp/cli.md" "$tmp/o" "$tmp/preset.md" 2>/dev/null; [ $? -ne 0 ]; check "a kit skill with no frontmatter fails" $? ""
bash "$script" --compose a b c 2>/dev/null; [ $? -eq 2 ]; check "--compose with the wrong arguments is a usage error" $? ""
bash "$script" nosuchpreset 2>/dev/null; [ $? -eq 2 ]; check "an unknown preset is a usage error" $? ""
mkdir -p "$tmp/up/presets/x"; cp "$script" "$tmp/up/"
bash "$script" ../presets/spec-across-repositories 2>"$tmp/err"; [ $? -eq 2 ]; check "a preset name that is a path is a usage error" $? "$(cat "$tmp/err")"
bash "$script" .. 2>/dev/null; [ $? -eq 2 ]; check "'..' is not a preset name" $? ""

echo "the preset's text (spec 296)"
cmd="$root/presets/spec-across-repositories/commands/speckit.specify.md"
has() { grep -qF -- "$2" "$cmd"; check "$1" $? "missing: $2"; }
has "the wrap point is there" '{CORE_TEMPLATE}'
has "the part before is marked" '## Before you specify'
has "the part after is marked" '## After you specify'
has "FR-002 the directory by the task number (backlog#403)" 'specs/BCKLG-<N>-<short name>'
has "backlog#403 the «Задачи» line under the title" '**Задачи**: BCKLG-<N>'
has "backlog#403 the task's spec is looked for and re-checked first" 'Look for the spec.md under `specs/` whose line'
has "FR-002 SPECIFY_FEATURE_DIRECTORY is set" 'SPECIFY_FEATURE_DIRECTORY'
has "FR-003 the engine's information" '`ecosystem`'
has "FR-003 an engine run is told by the file" '`.sdlc/run-input.json`'
has "FR-003 the file is the run's input, version 1" '`runInputVersion` 1'
has "FR-003 the record is the file's field" 'its `ecosystem` field'
has "FR-003 without the file it is by hand" 'Without the file you are working by hand'
has "FR-003 the file without the record stops" 'the file but no `ecosystem`, stop before writing anything'
grep -qF '`.sdlc/run-input.json`' "$root/presets/spec-across-repositories/README.md"; check "FR-003 the README names the file" $? ""
grep -qF 'galaxio.io/uses.galaxio-sdlc-orchestrator' "$root/catalog-info.yaml"; check "FR-003 the catalog declares the contract with the engine" $? ""
grep -q 'version: "0.4.0"' "$root/presets/spec-across-repositories/preset.yml"; check "the preset is 0.4.0" $? ""
has "FR-003 it stops when the information is missing" 'stop before writing'
has "FR-003 by hand it reads the catalog" 'catalog-info.yaml'
has "FR-004 the three verdicts" '`затронут`'
has "FR-004 unclear stays" '`неясно`'
has "FR-004 no other agent" 'no other agent'
has "FR-005 evidence by code" '`path:line`'
has "FR-005 evidence by the catalog chain" 'chain of relations'
has "FR-005 evidence by a principle" 'principle of the repository'"'"'s constitution'
has "FR-006 the table's section" '## Репозитории'
has "FR-006 the table's columns" '`Репозиторий`, `Вердикт`, `Что меняется`'
has "FR-007 requirements are marked" '`[все]`'
has "FR-008 the release order section" '## Порядок выпуска и контракты'
has "FR-009 the summary" '## Что специфицируется и как это будет работать'
has "readable: the statement is three to five short bullets" 'three to five short bullet lines'
has "readable: a not-affected row stays one short line" 'one short line'
has "readable: no reason is repeated" 'and say a reason shared by'
has "FR-010 the neighbours are checked" 'neighbours in'
has "FR-010 a conflict is critical" 'critical finding'
has "FR-011 one repository has one row" 'one row'
! grep -qiE 'start (an|another|a new) agent|spawn|subagent' "$cmd"; check "FR-004 the text starts no agent" $? ""
grep -qE '^strategy|strategy: "wrap"' "$root/presets/spec-across-repositories/preset.yml"; check "FR-012 the preset wraps, it does not replace" $? ""
! grep -q 'type: "template"' "$root/presets/spec-across-repositories/preset.yml"; check "FR-001 no template is wrapped" $? ""
[ "$(grep -c 'type: "' "$root/presets/spec-across-repositories/preset.yml")" -eq 1 ]; check "FR-001 only one command is provided" $? ""

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
