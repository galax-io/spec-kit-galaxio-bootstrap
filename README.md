# spec-kit-galaxio-bootstrap

Galaxio's working scratch template for spinning up a new project with our
**standard development process already wired in** — spec-kit (the same skills of Claude Code and Codex in every repository),
the issue↔PR↔milestone linkage gate, and a stack-agnostic `AGENTS.md`/`CLAUDE.md`.

The stack does not matter. The *process* is the same for every project, so this
repo captures the process once and stamps it into any new project.

## Usage

Install Copier once (isolated, not into a project venv):

```bash
uv tool install copier        # or:  pipx install copier
```

Scaffold a new project:

```bash
copier copy --trust gh:galax-io/spec-kit-galaxio-bootstrap ~/code/my-new-project
```

- `--trust` is required because the template runs post-gen tasks (optional `git init`). Without it Copier refuses to run tasks.
- Answer the prompts (or pass `--defaults --data key=value …` for non-interactive).
- Picking `stack` (scala-sbt / jvm-gradle / node / python / go / generic) pre-fills
  `build_test_cmd`, `dep_manifest`, `publish_mechanism`, the `.gitignore` build block,
  and emits a minimal build-file stub. Every default is overridable.

Pull later template/process changes into an already-scaffolded project:

```bash
cd ~/code/my-new-project
copier update --trust
```

Copier 3-way-merges the new template version against your local edits using the
`.copier-answers.yml` it dropped at scaffold time (keep that file committed). Your
filled-in `AGENTS.md` sections survive; new process rules land.

### Copier gotchas

- **`--trust` is mandatory** for this template (it has `_tasks`). Dry-run without
  side effects: add `--pretend`.
- **The task is skippable** — `do_git` defaults to `false`, so a plain `copier copy`
  writes files only.
- **The task re-runs on `copier update`.** If you scaffolded with `do_git: true`, that
  choice is saved in `.copier-answers.yml` and the `git init && git add && commit`
  task fires again on every update (an extra auto-commit). Leave it `false` and run
  `git init` yourself if you want full control. The `do_git` task also needs a
  configured git identity (`user.name` / `user.email`) or the commit step fails.
- **No Spec Kit install runs in your project** (the `run_speckit` question is gone): the kit
  is part of the template. The constitution is yours: copy and update never replace
  `.specify/memory/constitution.md`.
- **A global git `post-checkout` hook that exits non-zero breaks Copier**, because
  Copier clones the template and checks out a tag internally. If `copier copy gh:…`
  dies on `git checkout`, that's the cause — fix the hook or run with a clean
  `GIT_CONFIG_GLOBAL`.

## Adopting a repository that already exists

`copier copy` into a repository with its own `AGENTS.md` and scripts would want to replace them,
and a later `copier update` would take every difference for a local edit. For a repository that
was not made from this template use `scripts/adopt.sh` instead:

```bash
scripts/adopt.sh --dry-run --org-repo galax-io/<repo> ~/code/<repo>   # what it would do
scripts/adopt.sh --org-repo galax-io/<repo> --tagline "…" ~/code/<repo>
```

It never replaces a file the repository has. The "Feature milestones (ALWAYS)" section is inserted
into the existing `AGENTS.md` (into `CLAUDE.md` when that is where the project keeps its own
guidance), before "## Commits & PRs", and the "Labels (ALWAYS)" section right after it; a section
the file already has is kept; files of the gate that are missing are added; a gate file that
exists is kept and reported as "same as" or "differs from" the template so the difference can be
reviewed; a missing `AGENTS.md` is rendered with copier. It creates no `.copier-answers.yml` and
does not touch `.claude/settings.json`, which registers the hook. Running it twice changes nothing.

`--refresh` also brings up to date what an earlier run put there: a gate file, or a section, that equals the
template of some released tag is replaced by the current one; one that equals no release is a local variant and
is kept, with a note. It needs a checkout of this repository with its tags.

The PR check is a workflow, `.github/workflows/linkage.yml`, added when the repository has none that runs `check-linkage.sh --pr`. It needs the organization secret `BACKLOG_READ_TOKEN`: a fine-grained token with read access to Issues and Metadata of the backlog repository only. The backlog is private, so the job's own token cannot read it, and the gate uses the second token for the calls about the backlog and for nothing else.

## What you get in a scaffolded project

```
AGENTS.md              # process (Boundaries / Milestones / Commits & PRs / Release)
                       #   + project placeholders (Role / Stack / Commands / Structure / …)
CLAUDE.md              # -> @AGENTS.md
.claude/
  settings.json        # PreToolUse(Bash) hook wiring + model alias pins (env)
  hooks/linkage-guard.sh   # ~0-token gate: blocks release tagging unless linkage holds
  agents/deep-researcher.md  # opus at xhigh, read-only research + Codex second opinion
  agents/infra-worker.md     # sonnet at high, mechanical [tier:light] changes
  agents/trivial-worker.md   # claude-haiku-5-5 at medium, very simple [tier:trivial] work
scripts/
  check-linkage.sh     # verifies issue <-> PR <-> milestone contract (gh + jq)
  check-speckit.sh     # fails when the Spec Kit kit differs from the template's
.claude/skills/speckit-*    # the Spec Kit kit: skills of Claude Code ...
.agents/skills/speckit-*    # ... and of Codex, 35 each, identical in every project
.specify/              # the kit's scripts, templates, extensions, presets, hooks; speckit-kit.sha256 lists every file
.specify/memory/       # the project's own constitution (starting point only; never replaced)
.github/workflows/speckit.yml   # runs check-speckit.sh on every pull request
specs/
.gitignore
```

## Model tiers

Work is routed by the reasoning it needs (see `AGENTS.md` → Agents & Models),
always on the newest model of each class: deep work (complex code, reviews,
research, specs, plans) runs on `claude-opus-5-5` / Codex `gpt-6.1-sol` at
xhigh effort; light work (task generation, mechanical infra) on
`claude-sonnet-5-5` / Codex `gpt-6.1-sol` at high effort; trivial work
(simple edits, context, bookkeeping) on `claude-haiku-5-5` / Codex
`gpt-6-luna` at medium effort. `.claude/settings.json` pins Claude Code's
`opus` / `sonnet` / `haiku` aliases to those models, and each sub-agent in
`.claude/agents/` carries its tier's model and effort. `scripts/build-speckit-kit.sh`
(through `setup-speckit.sh`) writes the deep or light alias as a `model:` line into
each Claude Code spec-kit skill's frontmatter (the model only, not the effort).
Codex reads no `model:` line; its tier comes from how Codex is run:

| tier | skills |
|---|---|
| deep (`SPECKIT_DEEP_MODEL`, default `opus`) | specify, clarify, plan, analyze, checklist, constitution, converge, bug-assess, harness-explore, harness-verify, spectest-gaps, spectest-plan |
| light (`SPECKIT_LIGHT_MODEL`, default `sonnet`) | tasks, taskstoissues, agent-context-update, git-*, changelog-*, worktrees-*, harness-init/status/report, spectest-coverage |
| unpinned (session model) | implement, bug-fix, bug-test, spectest-generate — they dispatch per-task sub-agents by `[tier:*]` |

The pins are part of the generated kit, so a project picks tier changes up with
`copier update --trust`.

## The Spec Kit kit

Every repository holds the same Spec Kit, byte for byte: the skills of Claude Code
(`.claude/skills/speckit-*`) and Codex (`.agents/skills/speckit-*`), 35 each, and the files
they run on under `.specify/`. It is **generated once, here**, by the pinned Spec Kit CLI
(`KIT_VERSION` in `scripts/build-speckit-kit.sh`), committed to `template/`, and listed with
its hashes in `.specify/speckit-kit.sha256`. Nothing runs `specify` in a project.

```bash
scripts/build-speckit-kit.sh           # regenerate template/ (needs `specify` at exactly KIT_VERSION, network, git)
scripts/build-speckit-kit.sh --check   # fail when template/ is stale; CI runs this
```

Changing Spec Kit (a new version, an extension, a preset) is a pull request to this
repository: bump `KIT_VERSION` or edit `setup-speckit.sh`, regenerate, tag, and the
projects take it with `copier update --trust` (or `scripts/adopt.sh --speckit <dir>`
for a repository not made from the template). In a project, `scripts/check-speckit.sh`
and the `speckit` workflow fail on any difference (`MODIFIED`, `MISSING`, `EXTRA`).

**First move of an existing repository onto the kit takes two steps**, because its
`.specify/` and skills were written by some other Spec Kit version and `copier update` would
meet 60-odd conflicts:

```bash
scripts/adopt.sh --speckit ~/code/repo     # the kit replaces what is there (--dry-run shows it); commit
cd ~/code/repo && copier update --trust    # only the process files change now; setup-speckit.sh is deleted
```

(`adopt.sh --speckit` alone is enough for a repository without `.copier-answers.yml`.) Later
releases need `copier update --trust` only.

Left out of the kit, because they differ on every run or belong to one checkout: the CLI's
registries and integration manifests, the extension cache and backups, `feature.json` — git
ignores them in projects. `.specify/memory/` (the constitution) is the project's own.

## spec-kit components installed

| kind      | id                    | source                                            | notes |
|-----------|-----------------------|---------------------------------------------------|-------|
| extension | `agent-context`       | catalog (native)                                  | manages CLAUDE.md/AGENTS.md context |
| extension | `bug`                 | catalog (native)                                  | bug triage workflow |
| extension | `git`                 | catalog (native)                                  | feature-branch workflow |
| extension | `worktrees`           | `dango85/spec-kit-worktree-parallel` v1.3.2       | parallel git worktrees |
| extension | `harness`             | `formin/spec-kit-harness` v1.0.0                  | research/verification harness |
| extension | `spectest`            | `jigarkhwar/spec-kit-spectest` v1.1.0    | test generation (fork — see below) |
| extension | `changelog`           | `jigarkhwar/spec-kit-changelog` v1.2.0   | changelog/release notes (fork — see below) |
| preset    | `claude-ask-questions`| `0xrafasec/spec-kit-preset-claude-ask-questions`  | native AskUserQuestion picker for clarify/checklist |

**Maintained in our forks:** the original `Quratulain-bilal` `spectest`/`changelog`
extensions were broken — their `v1.0.0` manifests fail `specify`'s validator
(spectest: commands not namespaced under the extension id; changelog: wrong
`requires` key, hook missing `command`, bare-string commands) and their commands
read the spec from `.specify/spec.md` instead of `specs/<feature>/spec.md`. We
maintain fixed copies in our own forks — these are the canonical source for this
template, not a temporary patch (pin each fork to a working tag, bump on re-tag):
[jigarkhwar/spec-kit-spectest](https://github.com/jigarkhwar/spec-kit-spectest),
[jigarkhwar/spec-kit-changelog](https://github.com/jigarkhwar/spec-kit-changelog).

## Notes / gotchas (learned the hard way)

- **No `--force` for normal installs.** `--force` reinstalls an extension *over* an
  existing (possibly customized) copy and overwrites its files. The installer is
  additive by default — it skips what's already installed.
- **`specify preset add` has no `--force`** — only `--from` / `--dev` / `--priority`.
- **Community installs are interactive.** `specify ... --from <url>` prompts
  `Untrusted Source — Continue? [y/N]`; non-interactively it aborts. `setup-speckit.sh`
  auto-answers `y`. Running an agent that does this may be blocked by a safety
  classifier when the external URL/repo originates from tool output rather than your
  own message — run the script yourself, or grant a Bash permission rule.
- **Claude Code and Codex both get every skill.** Spec Kit writes extension and
  preset skills into the default integration only, so `setup-speckit.sh` makes Codex the
  default, then Claude Code, and pins the models last. It runs only inside
  `scripts/build-speckit-kit.sh` (and the legacy `bootstrap.sh --speckit`).
- **One failed install must not abort the rest** — the installer collects failures
  and reports them at the end (don't reintroduce `set -e` aborts in the install loop).
