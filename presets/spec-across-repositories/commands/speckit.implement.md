## Before you implement: which spec, which task, which repository?

A feature of this organization has one specification, in `galax-io/galaxio-sdlc-backlog`, and its tasks may change
several repositories. In an engine run one call of this command does a whole user story: every task the call names,
in order. By hand it does every open task of the tasks file, as the base command does. Do steps 0 to 4 first, in this
session, with no other agent for any repository.

**One session per user story.** In a run the engine calls this command once for one user story (the tasks of
`tasks.md` in one repository with the same `[US<n>]`, or with none), naming all its open tasks, and for the next story
in a new session. A later call in a session that already did a story (a retry, or the engine's note on a failed gate)
does not do steps 0 to 3 again and does not read again the spec, the plan, the contracts or the code you read: read
again only what changed since (the engine's commits, a file the call's note names) or what you no longer have. Text
after the task ids in the arguments is the engine's note for this call: why the previous attempt failed, the items to
answer, the maintainer's instructions. The working copies hold only what the engine committed: check with git before
you trust what you remember of a change.

0. **The run.** You are in an engine run when the file `.sdlc/run-input.json` exists in the working copy: it is the
   run's input (`runInputVersion` 1), which the engine always writes. Read its fields `task`, `specDirectory`,
   `workingCopies`, `tasks`, `taskId` and `runId`. In a run nobody answers a question: where a step below needs
   one of these fields and the file lacks it, do not guess and do not ask; stop and name it in the answer (step 9).
   Without the file you are working by hand.
1. **The spec.** The task number is `BCKLG-<N>`, where `<N>` is the number of the feature's issue in
   `galax-io/galaxio-sdlc-backlog`: `task` in a run, else from the arguments (`BCKLG-<N>`, or a directory
   `specs/BCKLG-<N>-…`). By hand, ask for it if you do not have it; never invent one. Find its spec
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
   `speckit-tasks`. The spec's files are written in this working copy, the backlog's, whatever step 3 says of the
   others. Each file keeps the tasks line of step 1, and a `tasks.md` of several repositories names each task's
   repository as `[repo:<name>]`. In a run, the first line of each Markdown file the ladder writes is
   `<!-- generated: run <runId> -->`, so that the stage's gate does not judge it as the maintainer's input.
   If the wrapped specify stops (in a run, for one, when the input has no `ecosystem`), stop too: the task is
   `[!] — <what specify said>` (step 6), and no other file is written.
3. **The working copies.**
   - In a run, `workingCopies` maps each repository the work may change (`galax-io/<name>`) to the path of its
     working copy. The task's edits go only there.
   - By hand, read `catalog-info.yaml` of the repositories the spec affects (its `## Репозитории`, the verdict
     `затронут` or `неясно`) and use their clones next to this repository's main clone: the directory above
     `$(git rev-parse --path-format=absolute --git-common-dir)`, not the worktree you may be in. Say where you looked
     for a repository with no clone.
4. **The tasks.** In a run, the tasks to do are those the call names: the ids (`T<NNN>`) in the arguments after the spec
   directory and/or the field `tasks` of the run input (a list of ids, if present); `taskId` is read as the first of
   them, so that a run input with only `taskId` still names one task. They are all the open tasks of one user story,
   in the order named. If the call names none, stop and name it in the answer (step 9). By hand, the tasks are every
   open task (`- [ ]`) of `tasks.md`, phase by phase, as the base command does, or those the arguments name. A task
   whose dependencies are not `[X]` waits for them; a `[~]` or `[!]` task holds back only the tasks that depend on it.
   A task names its repository as `[repo:<name>]`, and its edit goes into that repository's working copy; a task
   without the label is for the spec's only repository. No open task: say so and stop.

Then implement as below, every named task in a run, every open task by hand. Read steps 5 to 9 first: they change what
the steps below say about the tasks, their marks, the checklists and the hooks.

{CORE_TEMPLATE}

## After you implement: the story, its marks and the answer

5. **Do the whole story.** In a run, do every named task in order and do not stop after the first one: for each, write
   the test first and see it fail, then the code, and run the tests of what you change while you work. When the last
   task is done, run the repository's lint, type check and whole test suite once, and fix what they find. Do not
   commit: the engine commits. By hand, do every open task phase by phase, as the base command does.
6. **The marks.** A task's mark is `[X]` when it is done; `[~] — <what it waits for>` when it waits for an event
   outside the run; `[!] — <why, with the evidence>` when the input makes it impossible. A task whose repository has
   no working copy is, in a run, `[~] — needs the working copy of galax-io/<name>`, which the engine opens before it
   calls again, and by hand `[!]`. In a run the engine writes the marks, `[X]` only once the story's gate has
   accepted it: do not change `tasks.md`'s marks, and name a mark for each task in the answer. By hand, write each
   task's mark in `tasks.md` as it is done, `[X]` for a done one, and keep every other line as it is.
   This step replaces what the steps above say about marking a task `[X]`.
7. **The checklists.** In a run, do not stop or ask about the checklists of the feature directory: nobody answers a
   run. Count them as below says, go on with the tasks, and give the unchecked items of each checklist in the answer.
   By hand, ask as below says.
8. **The hooks.** In a run, do not run or offer the optional hooks of `before_implement` and `after_implement` in
   `.specify/extensions.yml`: the engine commits and reviews the work. By hand they are offered as above.
9. **The answer.** In a run, answer only in the schema the engine gives in its instruction, and say there a mark per
   task, `tasks: [{id, mark, reason?}]`, with the reason for `[~]` or `[!]`, a field of the input that was missing
   (step 0), and the unchecked items of each checklist, if any. By hand, report each task and its mark, the files
   changed in each repository and the open tasks that are left.
