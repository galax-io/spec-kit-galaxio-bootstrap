# Preset `spec-across-repositories`

Wraps the Spec Kit `specify` command (only that one) so that a feature of the organization that spans
several repositories gets one specification, written in `galax-io/galaxio-sdlc-backlog`.

An engine run is told by the file `.sdlc/run-input.json` in the working copy (the run's input, `runInputVersion` 1);
its `ecosystem` field is the engine's record of the ecosystem. With the file but no `ecosystem` the command stops
before writing; without the file it works by hand.

**Before** the base command: the feature directory `specs/<issue number>-<name>`, the candidate
repositories (from the engine's `ecosystem`, or read by hand from the catalog), a verdict with evidence
for each. **After** it, the preset adds to the specification:

- `## Репозитории`: a table row per repository, with `Репозиторий`, `Вердикт` (`затронут`, `не затронут` or `неясно`), `Что меняется` and `Основание`, which names its kind of evidence.
- `[<repository>]` on each functional requirement: the repository it is for, or `[все]` when it is for all of them.
- `## Порядок выпуска и контракты`: a numbered release order and what one repository gives another, or «Нет: затронут один репозиторий».
- `## Что специфицируется и как это будет работать`: at the top, three to five short lines of one sentence each.
- A check against the constitutions of this repository, the affected ones and their catalog neighbours: a conflict is a critical finding in `checklists/requirements.md`.

The list is a summary. The full rule is the text of `commands/speckit.specify.md`; where the two differ, the
text of the command is right.

The preset is not installed by `specify preset add` in a repository. `scripts/build-speckit-layer.sh`
installs it in a scratch project and keeps the two resulting skill files under
`layers/spec-across-repositories/`; `scripts/adopt.sh --speckit --overlay spec-across-repositories`
puts them in the backlog. The spec template is not wrapped: a wrapped template needs the preset registry
and PyYAML to resolve, which the repositories do not have.
