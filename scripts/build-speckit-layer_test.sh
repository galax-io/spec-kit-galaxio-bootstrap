#!/usr/bin/env bash
#
# build-speckit-layer_test.sh — tests for scripts/build-speckit-layer.sh and the preset text.
#
# Hermetic: no CLI. The composition (--compose) is run on small files, and the build on a checkout of
# small files with a stand-in for the CLI. What is under test is the promise of the layer: for each
# command the preset wraps, the kit's frontmatter (and so its model pin) and the kit's whole command
# are kept, the preset's text with that command's markers is before and after it, and anything else
# fails the build. The preset's
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

printf -- '---\nname: "speckit-implement"\n---\n\n## User Input\n\nDo the thing.\n' > "$tmp/kit-implement.md"
printf '## Before you implement\n\nsteps\n\n{CORE_TEMPLATE}\n\n## After you implement\n\nchecks\n' > "$tmp/preset-implement.md"
good | sed 's/you specify/you implement/' > "$tmp/cli-implement.md"
bash "$script" --compose "$tmp/kit-implement.md" "$tmp/cli-implement.md" "$tmp/o" "$tmp/preset-implement.md" 2>"$tmp/err"; check "an implement skill composes with the implement markers" $? "$(cat "$tmp/err")"
bash "$script" --compose "$tmp/kit-implement.md" "$tmp/cli.md" "$tmp/o" "$tmp/preset.md" 2>"$tmp/err"; [ $? -ne 0 ] && grep -q 'not before' "$tmp/err"; check "an implement skill with the specify markers fails" $? "$(cat "$tmp/err")"

echo "build: the commands the preset wraps (backlog#456)"
# A checkout of its own: the script, a kit of two commands, presets, and a stand-in for the CLI on PATH that
# does what the CLI does to a wrapped command: its own frontmatter and heading, the preset's text around the kit's body.
up="$tmp/build"; mkdir -p "$up/scripts" "$up/bin" "$up/template/.specify/memory"
cp "$script" "$up/scripts/"; echo 'KIT_VERSION=1.2.2' > "$up/scripts/build-speckit-kit.sh"; : > "$up/template/.specify/memory/constitution.md"
for c in specify implement; do
  for d in .claude .agents; do
    mkdir -p "$up/template/$d/skills/speckit-$c"
    { printf -- '---\nname: "speckit-%s"\n' "$c"; [ "$d" = .claude ] && echo 'model: opus'; printf -- '---\n\n## User Input\n\nThe kit %s.\n' "$c"; } > "$up/template/$d/skills/speckit-$c/SKILL.md"
  done
done
cat > "$up/bin/specify" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  version) echo "CLI Version 1.2.2" ;;
  integration) echo "$3" > .integration ;;
  preset)
    d=.claude; [ "$(cat .integration)" = codex ] && d=.agents
    for f in "$4"/commands/*.md; do
      skill="$d/skills/$(basename "$f" .md | tr . -)/SKILL.md"
      awk 'c>=2{print} /^---$/{c++}' "$skill" > .body
      { printf -- '---\nname: cli\n---\n\n# Skill\n\n'; awk '$0=="{CORE_TEMPLATE}"{while ((getline l < ".body") > 0) print l; next} {print}' "$f"; } > .skill
      mv .skill "$skill"
    done ;;
esac
EOF
chmod +x "$up/bin/specify"
# preset <name> <command>:<strategy> [<marker verb>]...: a preset that names each command with its strategy;
# each command's text has the markers of its own verb, or of the one given.
preset() {
  local name="$1" spec cmd verb; shift; mkdir -p "$up/presets/$name/commands"
  { printf 'schema_version: "1.0"\n\npreset:\n  id: "%s"\n  version: "0.1.0"\n\nprovides:\n  templates:\n' "$name"
    for spec in "$@"; do
      cmd="${spec%%:*}"; printf '    - type: "command"\n      name: "speckit.%s"\n      file: "commands/speckit.%s.md"\n      description: "x"\n      strategy: "%s"\n' "$cmd" "$cmd" "$(echo "$spec" | cut -d: -f2)"
    done
    printf '\ntags:\n  - "x"\n'; } > "$up/presets/$name/preset.yml"
  for spec in "$@"; do
    cmd="${spec%%:*}"; verb="$(echo "$spec" | cut -d: -f3)"; verb="${verb:-$cmd}"
    printf '## Before you %s\n\nsteps of %s\n\n{CORE_TEMPLATE}\n\n## After you %s\n\nchecks of %s\n' "$verb" "$cmd" "$verb" "$cmd" > "$up/presets/$name/commands/speckit.$cmd.md"
  done
}
build() { PATH="$up/bin:$PATH" bash "$up/scripts/build-speckit-layer.sh" "$@"; }
preset one specify:wrap
preset two specify:wrap implement:wrap
preset replaced specify:wrap implement:replace
preset none implement:replace
preset crossed specify:wrap implement:wrap:specify
layer="$up/layers/two"
skills=".agents/skills/speckit-implement/SKILL.md .agents/skills/speckit-specify/SKILL.md .claude/skills/speckit-implement/SKILL.md .claude/skills/speckit-specify/SKILL.md"

build two >"$tmp/out" 2>&1; check "a preset that wraps two commands builds" $? "$(cat "$tmp/out")"
n=0; for f in $skills; do [ -f "$layer/$f" ] && n=$((n + 1)); done; [ "$n" -eq 4 ]; check "the layer holds both skills for both integrations" $? "$(cd "$layer" 2>/dev/null && find . -type f)"
[ "$(find "$layer" -type f | wc -l)" -eq 5 ]; check "and nothing else but the overlay manifest" $? "$(cd "$layer" 2>/dev/null && find . -type f)"
grep -q '^model: opus$' "$layer/.claude/skills/speckit-implement/SKILL.md" && grep -q '^name: "speckit-implement"$' "$layer/.agents/skills/speckit-implement/SKILL.md" && ! grep -q '^name: cli$' "$layer/.agents/skills/speckit-implement/SKILL.md"; check "each skill has its kit's frontmatter" $? ""
r=0; for c in specify implement; do for d in .claude .agents; do
  f="$layer/$d/skills/speckit-$c/SKILL.md"
  awk -v c="$c" '$0=="## Before you " c{b=NR} $0=="The kit " c "."{k=NR} $0=="## After you " c{a=NR} END{exit !(b && k && a && b<k && k<a)}' "$f" || r=1
done; done
check "each skill has its own markers around its kit's body" "$r" ""
! grep -q 'you specify' "$layer/.claude/skills/speckit-implement/SKILL.md" && ! grep -q 'you implement' "$layer/.claude/skills/speckit-specify/SKILL.md"; check "no skill carries the other's markers" $? ""
[ "$(grep -c . "$layer/.specify/speckit-overlay.sha256" 2>/dev/null)" -eq 4 ] && [ "$(awk '{print $2}' "$layer/.specify/speckit-overlay.sha256" | tr '\n' ' ')" = "$skills " ]; check "one overlay manifest lists the four files" $? "$(cat "$layer/.specify/speckit-overlay.sha256" 2>/dev/null)"
( cd "$layer" && sha256sum -c .specify/speckit-overlay.sha256 2>/dev/null || shasum -a 256 -c .specify/speckit-overlay.sha256 ) >/dev/null 2>&1; check "with each file's hash" $? ""
build --check two >"$tmp/out" 2>&1; check "--check passes on the layer just built" $? "$(cat "$tmp/out")"
echo drift >> "$layer/.agents/skills/speckit-implement/SKILL.md"
build --check two >"$tmp/out" 2>&1; [ $? -eq 1 ] && grep -q 'speckit-implement' "$tmp/out"; check "--check fails when one skill drifts, and names it" $? "$(cat "$tmp/out")"
build one >"$tmp/out" 2>&1; build two >>"$tmp/out" 2>&1
cmp -s "$up/layers/one/.claude/skills/speckit-specify/SKILL.md" "$layer/.claude/skills/speckit-specify/SKILL.md" && cmp -s "$up/layers/one/.agents/skills/speckit-specify/SKILL.md" "$layer/.agents/skills/speckit-specify/SKILL.md"; check "wrapping a second command leaves the specify skill's bytes unchanged" $? "$(cat "$tmp/out")"
grep -q 'speckit-specify' "$up/layers/one/.specify/speckit-overlay.sha256" && [ "$(grep -c . "$up/layers/one/.specify/speckit-overlay.sha256")" -eq 2 ]; check "a preset of one command still lists its two files" $? ""
build replaced >"$tmp/out" 2>&1 && [ ! -e "$up/layers/replaced/.claude/skills/speckit-implement" ] && [ "$(grep -c . "$up/layers/replaced/.specify/speckit-overlay.sha256")" -eq 2 ]; check "a command the preset does not wrap is not in the layer" $? "$(cat "$tmp/out")"
build none >"$tmp/out" 2>&1; [ $? -eq 1 ] && grep -q 'wraps no command' "$tmp/out"; check "a preset that wraps no command fails" $? "$(cat "$tmp/out")"
build crossed >"$tmp/out" 2>&1; [ $? -eq 1 ] && grep -q 'not before' "$tmp/out" && [ ! -e "$up/layers/crossed" ]; check "a command whose text has another command's markers fails" $? "$(cat "$tmp/out")"

echo "the preset's text (spec 296)"
cmd="$root/presets/spec-across-repositories/commands/speckit.specify.md"
has() { grep -qF -- "$2" "$cmd"; check "$1" $? "missing: $2"; }
has "the wrap point is there" '{CORE_TEMPLATE}'
has "the part before is marked" '## Before you specify'
has "the part after is marked" '## After you specify'
has "FR-002 the directory by the task number (backlog#403)" 'specs/BCKLG-<N>-<short name>'
has "backlog#403 the «Задачи» line under the title" '**Задачи**: BCKLG-<N>'
has "backlog#403 its English spelling" '**Tasks**: BCKLG-<N>'
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
grep -q 'version: "0.5.0"' "$root/presets/spec-across-repositories/preset.yml"; check "the preset is 0.5.0" $? ""
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
[ "$(grep -c 'strategy: "wrap"' "$root/presets/spec-across-repositories/preset.yml")" -eq "$(grep -c 'type: "' "$root/presets/spec-across-repositories/preset.yml")" ]; check "FR-012 the preset wraps, it does not replace" $? ""
! grep -q 'type: "template"' "$root/presets/spec-across-repositories/preset.yml"; check "FR-001 no template is wrapped" $? ""
[ "$(grep -c 'type: "' "$root/presets/spec-across-repositories/preset.yml")" -eq 2 ] && grep -q 'name: "speckit.specify"' "$root/presets/spec-across-repositories/preset.yml" && grep -q 'name: "speckit.implement"' "$root/presets/spec-across-repositories/preset.yml"; check "FR-001 two commands are provided, specify and implement (backlog#456)" $? ""

echo "the implement text (backlog#456)"
cmd="$root/presets/spec-across-repositories/commands/speckit.implement.md"
grep -q 'file: "commands/speckit.implement.md"' "$root/presets/spec-across-repositories/preset.yml"; check "FR-001 the preset names the implement text" $? ""
has "the wrap point is there" '{CORE_TEMPLATE}'
has "the part before is marked" '## Before you implement'
has "the part after is marked" '## After you implement'
has "FR-001 the spec by its tasks line" '**Задачи**: BCKLG-<N>'
has "FR-001 the tasks line's English spelling" '**Tasks**: …'
has "FR-001 the spec is found as the wrapped specify finds it" 'as the wrapped specify does'
has "FR-001 the feature directory is set" 'SPECIFY_FEATURE_DIRECTORY'
has "FR-001 an engine run is told by the file" '`.sdlc/run-input.json`'
has "FR-001 the spec directory of the run" '`specDirectory`'
has "FR-001 the ladder: tasks from the plan" '`speckit-tasks`'
has "FR-001 the ladder: plan from the spec" '`speckit-plan`'
has "FR-001 the ladder: a short spec" 'a short spec'
has "FR-001 the ladder: specify" '`speckit-specify`'
has "FR-001 a generated file is marked in a run" '`<!-- generated: run <runId> -->`'
has "FR-003 the working copies of a run" '`workingCopies`'
has "FR-001 by hand from the catalog" 'catalog-info.yaml'
has "FR-001 by hand from the neighbouring clones" 'clones next to this repository'
has "FR-001 the task given in a run" '`taskId`'
has "FR-001 else the next open one by phases and dependencies" 'phases and dependencies'
has "FR-003 a task names its repository" '`[repo:<name>]`'
has "FR-006 stop after the one task" 'Do not go on to the next task'
has "FR-006 done is [X]" '`[X]`'
has "FR-006 waiting is [~] with the reason" '`[~] — '
has "FR-006 cannot is [!] with the reason" '`[!] — '
has "FR-001 no optional hooks in a run: before" '`before_implement`'
has "FR-001 no optional hooks in a run: after" '`after_implement`'
has "FR-001 the answer in the engine's schema" 'schema the engine'
has "FR-001 in a run the checklists do not stop the task" 'do not stop or ask about the checklists'
has "FR-001 the answer counts the unchecked checklist items" 'unchecked items of each checklist'
! grep -qiE 'start (an|another|a new) agent|spawn|subagent' "$cmd"; check "the text starts no agent" $? ""
for w in '`speckit.implement`' '`workingCopies`' '`<!-- generated: run <runId> -->`' 'one task'; do
  grep -qF -- "$w" "$root/presets/spec-across-repositories/README.md"; check "the README says what the implement wrap adds: $w" $? ""
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
