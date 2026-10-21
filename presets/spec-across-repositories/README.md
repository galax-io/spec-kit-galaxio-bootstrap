# Preset `spec-across-repositories`

Wraps the Spec Kit `specify` command (only that one) so that a feature of the organization that spans
several repositories gets one specification, written in `galax-io/galaxio-sdlc-backlog`.

An engine run is told by the file `.sdlc/run-input.json` in the working copy (the run's input, `runInputVersion` 1);
its `ecosystem` field is the engine's record of the ecosystem. With the file but no `ecosystem` the command stops
before writing; without the file it works by hand.

**Before** the base command: the feature directory `specs/<issue number>-<name>`, the candidate
repositories (from the engine's `ecosystem`, or read by hand from the catalog), a verdict with evidence
for each.

**After** it, in steps 4 and 5 of `commands/speckit.specify.md`, the preset adds to the specification:

- The `## Репозитории` table, with the columns `Репозиторий`, `Вердикт`, `Что меняется`, `Основание`, has
  one row per repository, with the verdict `затронут`, `не затронут` or `неясно` and the kind of evidence
  said in `Основание`.
- Each functional requirement is marked with the repository it is for, as `[<repository>]` with the
  repository's name for `<repository>`, or `[все]` when it is for all of them.
- The `## Порядок выпуска и контракты` section gives the numbered order in which the repositories are
  released and, for each dependency between them, what one gives the other, or only the words
  «Нет: затронут один репозиторий» when one repository is affected.
- The `## Что специфицируется и как это будет работать` section, at the top of the specification, says in
  three to five short bullet lines what is specified and how it will work, for a reader who will read
  nothing else.
- The specification is checked against the constitutions of the repository it is written in, of every
  repository with the verdict `затронут` or `неясно` and of their neighbours in the catalog, with the
  findings in `checklists/requirements.md`, not in the specification: a conflict is a critical finding and
  a constitution that is missing is listed as not checked.

The preset is not installed by `specify preset add` in a repository. `scripts/build-speckit-layer.sh`
installs it in a scratch project and keeps the two resulting skill files under
`layers/spec-across-repositories/`; `scripts/adopt.sh --speckit --overlay spec-across-repositories`
puts them in the backlog. The spec template is not wrapped: a wrapped template needs the preset registry
and PyYAML to resolve, which the repositories do not have.
