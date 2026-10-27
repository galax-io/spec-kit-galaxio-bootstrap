## Before you implement: which spec, which task, which repository?

A feature of this organization has one specification, in `galax-io/galaxio-sdlc-backlog`, and its tasks may change
several repositories. This command does one task of it per call. Do steps 0 to 4 first, in this session, with no
other agent for any repository.

0. **The run.** You are in an engine run when the file `.sdlc/run-input.json` exists in the working copy: it is the
   run's input (`runInputVersion` 1), which the engine always writes. Read its fields `task`, `specDirectory`,
   `workingCopies`, `taskId` and `runId`; any of them may be absent. Without the file you are working by hand.
1. **The spec.** The task number is `BCKLG-<N>`, where `<N>` is the number of the feature's issue in
   `galax-io/galaxio-sdlc-backlog`: `task` in a run, else from the arguments (`BCKLG-<N>`, or a directory
   `specs/BCKLG-<N>-…`). Ask for it if you do not have it; never invent one. Find its spec
   as the wrapped specify does: the spec.md under `specs/` whose line `**Задачи**: BCKLG-<N>[, BCKLG-<M>…]`
   under its title names `BCKLG-<N>`, written `**Tasks**: …` in a repository whose files are English only and
   read alike; a spec.md without the line counts as the spec of the task its directory is named by
   (`specs/<N>-…` or `specs/BCKLG-<N>-…`). In a run, `specDirectory` is that directory; if its spec names another
   task, stop and say so. Two such specs: stop and say which. None: the directory is
   `specs/BCKLG-<N>-<short name>`. Use the directory as the feature directory in every step below (set
   `SPECIFY_FEATURE_DIRECTORY` to it).
2. **The ladder.** The input is the directory's `tasks.md`. Without it, call `speckit-tasks` to write it from
   `plan.md`; without `plan.md`, call `speckit-plan`, then `speckit-tasks`; without `spec.md`, call
   `speckit-specify` for a short spec from the task's text (the arguments, else the issue), then `speckit-plan` and
   `speckit-tasks`. Each file keeps the tasks line of step 1, and a `tasks.md` of several repositories names each
   task's repository as `[repo:<name>]`. In a run, the first line of each Markdown file the ladder writes is
   `<!-- generated: run <runId> -->`, so that the stage's gate does not judge it as the maintainer's input.
3. **The working copies.**
   - In a run, `workingCopies` maps each repository the work may change (`galax-io/<name>`) to the path of its
     working copy. Edit files only there.
   - By hand, read `catalog-info.yaml` of the repositories the spec affects (its `## Репозитории`, the verdict
     `затронут` or `неясно`) and use their clones next to this repository (`../<name>`). A repository with no clone
     is said so.
4. **The task.** Do one task: the one the arguments name (`T<NNN>`), in a run `taskId`; else the first open task
   (`- [ ]`) by the phases and dependencies of `tasks.md`, whose earlier phase is done and whose dependencies are
   `[X]`. A task names its repository as `[repo:<name>]`, and its edit goes into that repository's working copy; a
   task without the label is for the spec's only repository. No open task: say so and stop.

Then implement as below, that one task only. Read steps 5 to 9 first: they change what the steps below say about
every task, its mark, the checklists and the hooks.

{CORE_TEMPLATE}

## After you implement: one task, its mark and the answer

5. **Stop after the task.** Do not go on to the next task, even when it is open and in the same phase; the next
   call does it.
6. **The mark.** The task's mark is `[X]` when it is done; `[~] — <what it waits for>` when it waits for an event
   outside the run; `[!] — <why, with the evidence>` when the input makes it impossible. A task whose repository has
   no working copy is `[!]`. In a run the engine writes the marks, `[X]` only once the task's gate has accepted it:
   do not change `tasks.md`'s marks, and name the mark in the answer. By hand, in `tasks.md`, change only that task's
   mark, and keep every other line as it is.
   This step replaces what the steps above say about marking a task `[X]`.
7. **The checklists.** In a run, do not stop or ask about the checklists of the feature directory: nobody answers a
   run. Count them as below says, go on with the task, and give the unchecked items of each checklist in the answer.
   By hand, ask as below says.
8. **The hooks.** In a run, do not run or offer the optional hooks of `before_implement` and `after_implement` in
   `.specify/extensions.yml`: the engine commits and reviews the work. By hand they are offered as above.
9. **The answer.** In a run, answer only in the schema the engine gives in its instruction, and say there the task's
   id, its mark (step 6), for `[~]` or `[!]` the reason, and the unchecked items of each checklist, if any. By hand, report the task, its mark, the files changed in each
   repository and the next open task.
