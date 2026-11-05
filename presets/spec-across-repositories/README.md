# Preset `spec-across-repositories`

Wraps three Spec Kit commands, `speckit.specify`, `speckit.implement` and `speckit.tasks`, so that a feature of the
organization that spans several repositories gets one specification, written in `galax-io/galaxio-sdlc-backlog`, and
its tasks are coarse and each task is done in its own repository.

## `speckit.specify`

An engine run is told by the file `.sdlc/run-input.json` in the working copy (the run's input, `runInputVersion` 1);
its `ecosystem` field is the engine's record of the ecosystem. With the file but no `ecosystem` the command stops
before writing; without the file it works by hand.

**Before** the base command: the task's spec, when `specs/` has one, found by the line
`**Задачи**: BCKLG-<N>` under its title and checked against the task instead of writing another; else the
feature directory `specs/BCKLG-<N>-<name>` with that line, `**Tasks**:` where the files are English only
(backlog#403); the candidate repositories (from the
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

## `speckit.implement`

The same file `.sdlc/run-input.json` tells it an engine run; its optional fields `task`, `specDirectory`,
`workingCopies`, `tasks`, `taskId`, `runId` and `implementPolicy` are the run's (`commands/speckit.implement.md` is the full text and wins
where they differ).

The optional `implementPolicy` is `{version: 1, name: "final-review-v1", workflowRevision: <string>}`. Its absence
means legacy; the policy is never inferred from a branch. Final-review calls implement one whole phase per call in the
same session, with only necessary automatic checkpoints and no intermediate agent gates. Final review follows the last
phase. The legacy run still uses one session and call per story; manual operation is unchanged.

**Before** the base command:

- The spec: found by its tasks line, as the wrapped specify finds it, and used as the feature directory
  (`SPECIFY_FEATURE_DIRECTORY`).
- The ladder: without `tasks.md` it calls `speckit-tasks`; without `plan.md`, `speckit-plan` first; without
  `spec.md`, a short `speckit-specify` from the task's text first. In a run each Markdown file it writes starts with
  `<!-- generated: run <runId> -->`, so that the stage's gate does not judge it.
- The working copies: `workingCopies` of the run, or by hand the clones next to this repository of the repositories
  the spec affects, found by their `catalog-info.yaml`.
- The tasks: in a run, those the call names (the ids after the spec directory and/or the field `tasks` of the input,
  all named phase tasks for final review or all open tasks of one legacy story, in order; `taskId` is read as the first of them); by hand every open task by
  the phases and dependencies of `tasks.md`. A task's `[repo:<name>]` names the working copy its edit goes into.

**After** it: in a legacy run it does a whole user story in one call; final review does a whole phase: every named task in order, test first for
each, the tests of what it changes run while it works, and the repository's lint, type check and whole test suite once
at the end; it does not commit, the engine does. It answers with a mark per task, `tasks: [{id, mark, reason?}]`
(`[X]`, `[~] — <what it waits for>` or `[!] — <why>`); the engine writes the marks, `[X]` when the engine accepts the work under its policy. By hand it does as the base command does: every open task phase by phase, each marked `[X]` in `tasks.md`. In a run
it does not stop to ask about unchecked checklist items but reports them, runs no optional hook of `before_implement`
or `after_implement`, and answers in the schema the engine gives.

## `speckit.tasks`

**After** the base command's rules, the tasks it writes are coarse, for both the legacy story call and the final-review phase call: a story's work
is a few tasks, not one per file; no task only commits (the engine commits); and no separate «tests first» task and
«implementation» task for the same change (a task is test first inside itself).

The preset is not installed by `specify preset add` in a repository. `scripts/build-speckit-layer.sh`
installs it in a scratch project and keeps the six resulting skill files (three commands, Claude Code and Codex) under
`layers/spec-across-repositories/`; `scripts/adopt.sh --speckit --overlay spec-across-repositories`
puts them in the backlog. The spec template is not wrapped: a wrapped template needs the preset registry
and PyYAML to resolve, which the repositories do not have.
