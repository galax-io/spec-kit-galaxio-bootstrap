---
name: "speckit-implement"
description: "Execute the implementation plan by processing and executing all tasks defined in tasks.md"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/implement.md"
---

# Speckit Implement Skill

## Before you implement: which spec, which task, which repository?

A feature of this organization has one specification, in `galax-io/galaxio-sdlc-backlog`, and its tasks may change
several repositories. In a legacy engine run one call of this command does a whole user story: every task the call
names, in order. Under `final-review-v1` it does one whole phase per call, with all phases in the same session.
By hand it does
every open task of the tasks file, as the base command does. Do steps 0 to 4 first, in this session, with no other agent
for any repository.

**Sessions.** In a legacy run the engine calls this command once for one user story (the tasks of
`tasks.md` in one repository with the same `[US<n>]`, or with none), naming all its open tasks, and for the next story
in a new session. A later call in a session that already did a story (a retry, or the engine's note on a failed gate)
does not do steps 0 to 3 again and does not read again the spec, the plan, the contracts or the code you read: read
again only what changed since (the engine's commits, a file the call's note names) or what you no longer have. Text
after the task ids in the arguments is the engine's note for this call: why the previous attempt failed, the items to
answer, the maintainer's instructions. For `final-review-v1`, use the same session for all phase calls and read only
changes or missing context on later calls. The working copies hold only what the engine committed: check with git before
you trust what you remember of a change.

0. **The run.** You are in an engine run when the file `.sdlc/run-input.json` exists in the working copy: it is the
   run's input (`runInputVersion` 1), which the engine always writes. Read its fields `task`, `specDirectory`,
   `workingCopies`, `tasks`, `taskId`, `runId` and optional `implementPolicy`.
   The absence of `implementPolicy` means legacy;
   `{version: 1, name: "final-review-v1", workflowRevision: <string>}` selects final review;
   never infer the policy from a branch name.
   In a run nobody answers a question: where a step below needs
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
   them, so that a run input with only `taskId` still names one task. For legacy they are all the open tasks of one
   user story; for `final-review-v1` they are the named tasks of the phase, in the order named. If the call names none,
   stop and name it in the answer (step 9). By hand, the tasks are every
   open task (`- [ ]`) of `tasks.md`, phase by phase, as the base command does, or those the arguments name. A task
   whose dependencies are not `[X]` waits for them; a `[~]` or `[!]` task holds back only the tasks that depend on it.
   A task names its repository as `[repo:<name>]`, and its edit goes into that repository's working copy; a task
   without the label is for the spec's only repository. No open task: say so and stop.

Then implement as below, every named task in a run, every open task by hand. Read steps 5 to 9 first: they change what
the steps below say about the tasks, their marks, the checklists and the hooks.


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before implementation)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_implement` key
- If the YAML cannot be parsed or is invalid, do not skip silently: tell the user that `.specify/extensions.yml` could not be read (include the parser error) and that no hooks were checked, including any mandatory (`optional: false`) hooks registered there, then continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing command invocations from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `$speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}

    Wait for the result of the hook command before proceeding to the Outline.
    ```
    After emitting the block above you MUST actually invoke the hook and wait for it to finish before continuing. Run it the same way you would run the command yourself in this agent/session (the invocation may differ from the literal `{command}` id shown above, e.g. a skills-mode agent runs it as `/skill:speckit-...` or `$speckit-...`). Emitting the block alone does not run the hook.
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Outline

1. Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Check checklists status** (if FEATURE_DIR/checklists/ exists):
   - Treat checklist markers as a read-only gate: scan checkbox state, report status, and ask before proceeding when needed; do NOT modify checklist files or markers
   - `checklists/requirements.md` is the built-in spec-quality checklist maintained by `$speckit-specify` and `$speckit-clarify`; custom checklists generated by `$speckit-checklist` are reviewer-owned requirements-quality review artifacts
   - For custom checklists, `[x]` means the reviewer determined the requirements-quality criterion is satisfied; it does NOT mean implementation work is complete
   - Scan all checklist files in the checklists/ directory
   - For each checklist, count:
     - Total items: All lines matching `- [ ]` or `- [X]` or `- [x]`
     - Checked items: Lines matching `- [X]` or `- [x]`
     - Unchecked items: Lines matching `- [ ]`
   - Create a status table:

     ```text
     | Checklist | Total | Checked | Unchecked | Status |
     |-----------|-------|---------|-----------|--------|
     | ux.md     | 12    | 12      | 0         | ✓ PASS |
     | test.md   | 8     | 5       | 3         | ✗ FAIL |
     | security.md | 6   | 6       | 0         | ✓ PASS |
     ```

   - Calculate overall status:
     - **PASS**: All checklists have 0 unchecked items
     - **FAIL**: One or more checklists have unchecked items

   - **If any checklist has unchecked items**:
     - Display the table with unchecked item counts
     - **STOP** and ask: "Some checklists have unchecked items. Do you want to proceed with implementation anyway? (yes/no)"
     - Wait for user response before continuing
     - If user says "no" or "wait" or "stop", halt execution
     - If user says "yes" or "proceed" or "continue", proceed to step 3

   - **If all checklists are checked**:
     - Display the table showing all checklists passed
     - Automatically proceed to step 3

3. Load and analyze the implementation context:
   - **REQUIRED**: Read tasks.md for the complete task list and execution plan
   - **REQUIRED**: Read plan.md for tech stack, architecture, and file structure
   - **IF EXISTS**: Read data-model.md for entities and relationships
   - **IF EXISTS**: Read contracts/ for API specifications and test requirements
   - **IF EXISTS**: Read research.md for technical decisions and constraints
   - **IF EXISTS**: Read .specify/memory/constitution.md for governance constraints
   - **IF EXISTS**: Read quickstart.md for integration scenarios

4. **Project Setup Verification**:
   - **REQUIRED**: Create/verify ignore files based on actual project setup:

   **Detection & Creation Logic**:
   - Check if the following command succeeds to determine if the repository is a git repo (create/verify .gitignore if so):

     ```sh
     git rev-parse --git-dir 2>/dev/null
     ```

   - Check if Dockerfile* exists or Docker in plan.md → create/verify .dockerignore
   - Check if .eslintrc* exists → create/verify .eslintignore
   - Check if eslint.config.* exists → ensure the config's `ignores` entries cover required patterns
   - Check if .prettierrc* exists → create/verify .prettierignore
   - Check if .npmrc or package.json exists → create/verify .npmignore (if publishing)
   - Check if terraform files (*.tf) exist → create/verify .terraformignore
   - Check if .helmignore needed (helm charts present) → create/verify .helmignore

   **If ignore file already exists**: Verify it contains essential patterns, append missing critical patterns only
   **If ignore file missing**: Create with full pattern set for detected technology

   **Common Patterns by Technology** (from plan.md tech stack):
   - **Node.js/JavaScript/TypeScript**: `node_modules/`, `dist/`, `build/`, `*.log`, `.env*`
   - **Python**: `__pycache__/`, `*.pyc`, `.venv/`, `venv/`, `dist/`, `*.egg-info/`
   - **Java**: `target/`, `*.class`, `*.jar`, `.gradle/`, `build/`
   - **C#/.NET**: `bin/`, `obj/`, `*.user`, `*.suo`, `packages/`
   - **Go**: `*.exe`, `*.test`, `vendor/`, `*.out`
   - **Ruby**: `.bundle/`, `log/`, `tmp/`, `*.gem`, `vendor/bundle/`
   - **PHP**: `vendor/`, `*.log`, `*.cache`, `*.env`
   - **Rust**: `target/`, `debug/`, `release/`, `*.rs.bk`, `*.rlib`, `*.prof*`, `.idea/`, `*.log`, `.env*`
   - **Kotlin**: `build/`, `out/`, `.gradle/`, `.idea/`, `*.class`, `*.jar`, `*.iml`, `*.log`, `.env*`
   - **C++**: `build/`, `bin/`, `obj/`, `out/`, `*.o`, `*.so`, `*.a`, `*.exe`, `*.dll`, `.idea/`, `*.log`, `.env*`
   - **C**: `build/`, `bin/`, `obj/`, `out/`, `*.o`, `*.a`, `*.so`, `*.exe`, `*.dll`, `autom4te.cache/`, `config.status`, `config.log`, `.idea/`, `*.log`, `.env*`
   - **Swift**: `.build/`, `DerivedData/`, `*.swiftpm/`, `Packages/`
   - **R**: `.Rproj.user/`, `.Rhistory`, `.RData`, `.Ruserdata`, `*.Rproj`, `packrat/`, `renv/`
   - **Universal**: `.DS_Store`, `Thumbs.db`, `*.tmp`, `*.swp`, `.vscode/`, `.idea/`

   **Tool-Specific Patterns**:
   - **Docker**: `node_modules/`, `.git/`, `Dockerfile*`, `.dockerignore`, `*.log*`, `.env*`, `coverage/`
   - **ESLint**: `node_modules/`, `dist/`, `build/`, `coverage/`, `*.min.js`
   - **Prettier**: `node_modules/`, `dist/`, `build/`, `coverage/`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
   - **Terraform**: `.terraform/`, `*.tfstate*`, `*.tfvars`, `.terraform.lock.hcl`
   - **Kubernetes/k8s**: `*.secret.yaml`, `secrets/`, `.kube/`, `kubeconfig*`, `*.key`, `*.crt`

5. Parse tasks.md structure and extract:
   - **Task phases**: Setup, Tests, Core, Integration, Polish
   - **Task dependencies**: Sequential vs parallel execution rules
   - **Task details**: ID, description, file paths, parallel markers [P]
   - **Execution flow**: Order and dependency requirements

6. Execute implementation following the task plan:
   - **Phase-by-phase execution**: Complete each phase before moving to the next
   - **Respect dependencies**: Run sequential tasks in order, parallel tasks [P] can run together
   - **Follow TDD approach**: Execute test tasks before their corresponding implementation tasks
   - **File-based coordination**: Tasks affecting the same files must run sequentially
   - **Validation checkpoints**: Verify each phase completion before proceeding

7. Implementation execution rules:
   - **Setup first**: Initialize project structure, dependencies, configuration
   - **Tests before code**: If you need to write tests for contracts, entities, and integration scenarios
   - **Core development**: Implement models, services, CLI commands, endpoints
   - **Integration work**: Database connections, middleware, logging, external services
   - **Polish and validation**: Unit tests, performance optimization, documentation

8. Progress tracking and error handling:
   - Report progress after each completed task
   - Halt execution if any non-parallel task fails
   - For parallel tasks [P], continue with successful tasks, report failed ones
   - Provide clear error messages with context for debugging
   - Suggest next steps if implementation cannot proceed
   - **IMPORTANT** For completed tasks, make sure to mark the task off as [X] in the tasks file.

9. Completion validation:
   - Verify all required tasks are completed
   - Check that implemented features match the original specification
   - Validate that tests pass and coverage meets requirements
   - Confirm the implementation follows the technical plan

Note: This command assumes a complete task breakdown exists in tasks.md. If tasks are incomplete or missing, suggest running `$speckit-tasks` first to regenerate the task list.

## Mandatory Post-Execution Hooks

**You MUST complete this section before reporting completion to the user.**

Check if `.specify/extensions.yml` exists in the project root.
- If it does not exist, or no hooks are registered under `hooks.after_implement`, skip to the Completion Report.
- If it exists, read it and look for entries under the `hooks.after_implement` key.
- If the YAML cannot be parsed or is invalid, do not skip silently: tell the user that `.specify/extensions.yml` could not be read (include the parser error) and that no hooks were checked, including any mandatory (`optional: false`) hooks registered there, then continue to the Completion Report.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing command invocations from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `$speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Mandatory hook** (`optional: false`) — **You MUST emit `EXECUTE_COMMAND:` for each mandatory hook**:
    ```
    ## Extension Hooks

    **Automatic Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    ```
    After emitting the block above you MUST actually invoke the hook and wait for it to finish before continuing. Run it the same way you would run the command yourself in this agent/session (the invocation may differ from the literal `{command}` id shown above, e.g. a skills-mode agent runs it as `/skill:speckit-...` or `$speckit-...`). Emitting the block alone does not run the hook.
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```

## Completion Report

Report final status with summary of completed work.

## Done When

- [ ] All tasks in tasks.md completed and marked `[X]`
- [ ] Implementation validated against specification, plan, and test coverage
- [ ] Extension hooks dispatched or skipped according to the rules in Mandatory Post-Execution Hooks above
- [ ] Completion reported to user with summary of completed work


## After you implement: the story, its marks and the answer

5. **Do the whole call.** In a run, do every named task in order and do not stop after the first one: for each, write
   the test first and see it fail, then the code, and run the tests of what you change while you work.
   For legacy, when the last task is done,
   run the repository's lint, type check and whole test suite once, and fix what they find. Under `final-review-v1`,
   run necessary automatic checks for the phase; run the full required suite after the last phase. Do not
   commit: the engine commits. The engine runs no intermediate agent gates; final review follows the last phase.
   By hand, do every open task
   phase by phase, as the base command does.
6. **The marks.** A task's mark is `[X]` when it is done; `[~] — <what it waits for>` when it waits for an event
   outside the run; `[!] — <why, with the evidence>` when the input makes it impossible. A task whose repository has
   no working copy is, in a run, `[~] — needs the working copy of galax-io/<name>`, which the engine opens before it
   calls again, and by hand `[!]`. In a run the engine writes the marks, `[X]` only when the engine accepts the work
   under its policy: do not change `tasks.md`'s marks, and name a mark for each task in the answer. By hand, write each
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
