# spec-kit-galaxio-bootstrap

Galaxio's working scratch template for spinning up a new project with our
**standard development process already wired in** — spec-kit (extensions + presets),
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

- `--trust` is required because the template runs post-gen tasks (spec-kit install,
  optional `git init`). Without it Copier refuses to run tasks.
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
- **Tasks are skippable** — `run_speckit` and `do_git` both default to `false`, so a
  plain `copier copy` writes files only.
- **Tasks re-run on `copier update`.** If you scaffolded with `do_git: true`, that
  choice is saved in `.copier-answers.yml` and the `git init && git add && commit`
  task fires again on every update (an extra auto-commit). Re-running `run_speckit`
  is harmless (additive install). Leave both `false` and run `setup-speckit.sh` /
  `git init` yourself if you want full control. The `do_git` task also needs a
  configured git identity (`user.name` / `user.email`) or the commit step fails.
- **A global git `post-checkout` hook that exits non-zero breaks Copier**, because
  Copier clones the template and checks out a tag internally. If `copier copy gh:…`
  dies on `git checkout`, that's the cause — fix the hook or run with a clean
  `GIT_CONFIG_GLOBAL`.

## What you get in a scaffolded project

```
AGENTS.md              # process (Boundaries / Milestones / Commits & PRs / Release)
                       #   + project placeholders (Role / Stack / Commands / Structure / …)
CLAUDE.md              # -> @AGENTS.md
.claude/
  settings.json        # PreToolUse(Bash) hook wiring
  hooks/linkage-guard.sh   # ~0-token gate: blocks release tagging unless linkage holds
scripts/
  check-linkage.sh     # verifies issue <-> PR <-> milestone contract (gh + jq)
setup-speckit.sh       # installs spec-kit extensions + presets
specs/  .specify/      # spec-kit working dirs
.gitignore
```

## spec-kit components installed

| kind      | id                    | source                                            | notes |
|-----------|-----------------------|---------------------------------------------------|-------|
| extension | `agent-context`       | catalog (native)                                  | manages CLAUDE.md/AGENTS.md context |
| extension | `bug`                 | catalog (native)                                  | bug triage workflow |
| extension | `git`                 | catalog (native)                                  | feature-branch workflow |
| extension | `worktrees`           | `dango85/spec-kit-worktree-parallel` v1.3.2       | parallel git worktrees |
| extension | `harness`             | `formin/spec-kit-harness` v1.0.0                  | research/verification harness |
| extension | `spectest`            | `jigarkhwar/spec-kit-spectest` v1.0.0-galaxio.1    | test generation (fork — see below) |
| extension | `changelog`           | `jigarkhwar/spec-kit-changelog` v1.0.0-galaxio.1   | changelog/release notes (fork — see below) |
| preset    | `claude-ask-questions`| `0xrafasec/spec-kit-preset-claude-ask-questions`  | native AskUserQuestion picker for clarify/checklist |

**Pinned to forks:** `spectest` and `changelog` ship upstream `v1.0.0` manifests that
fail `specify`'s validator (spectest: commands not namespaced under the extension id;
changelog: wrong `requires` key, hook missing `command`, bare-string commands). Fixes
are filed upstream and `setup-speckit.sh` pins to our forks' `v1.0.0-galaxio.1` tag
until they merge:
[spectest#2](https://github.com/Quratulain-bilal/spec-kit-spectest/pull/2),
[changelog#3](https://github.com/Quratulain-bilal/spec-kit-changelog/pull/3).
Repoint to `Quratulain-bilal` once a fixed upstream tag ships.

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
- **One failed install must not abort the rest** — the installer collects failures
  and reports them at the end (don't reintroduce `set -e` aborts in the install loop).
