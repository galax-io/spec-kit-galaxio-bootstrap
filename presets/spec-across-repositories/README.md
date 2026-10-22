# Preset `spec-across-repositories`

Wraps the Spec Kit `specify` command (only that one) so that a feature of the organization that spans
several repositories gets one specification, written in `galax-io/galaxio-sdlc-backlog`.

An engine run is told by the file `.sdlc/run-input.json` in the working copy (the run's input, `runInputVersion` 1);
its `ecosystem` field is the engine's record of the ecosystem. With the file but no `ecosystem` the command stops
before writing; without the file it works by hand.

**Before** the base command: the task's spec, when `specs/` has one, found by the line
`**Задачи**: BCKLG-<N>` under its title and checked against the task instead of writing another; else the
feature directory `specs/BCKLG-<N>-<name>` with that line (backlog#403); the candidate repositories (from the
engine's `ecosystem`, or read by hand from the catalog), a verdict with evidence for each.

**After** it, the command adds these to the spec, in its language (`commands/speckit.specify.md` is the full
text and wins where they differ):

- `## Репозитории`: a table with exactly the columns `Репозиторий`, `Вердикт`, `Что меняется`, `Основание`,
  one row per repository with its verdict and the kind of its evidence, so one row for a feature of one
  repository.
- Requirement marks: each functional requirement names the repository it is for as `[<repository>]`, or
  `[все]` when it is for all of them.
- `## Порядок выпуска и контракты`: a numbered order in which the repositories are released and, for each
  dependency between them, what one repository gives the other, or only the words
  «Нет: затронут один репозиторий» when one is affected.
- `## Что специфицируется и как это будет работать`: at the top of the spec, three to five short bullet
  lines of one sentence each, saying what is specified and how it will work across the repositories.

Then it checks the spec against the constitutions of the affected repositories and their neighbours and
writes its findings in `checklists/requirements.md`, not in the spec.

The preset is not installed by `specify preset add` in a repository. `scripts/build-speckit-layer.sh`
installs it in a scratch project and keeps the two resulting skill files under
`layers/spec-across-repositories/`; `scripts/adopt.sh --speckit --overlay spec-across-repositories`
puts them in the backlog. The spec template is not wrapped: a wrapped template needs the preset registry
and PyYAML to resolve, which the repositories do not have.
