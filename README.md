# spec-kit-bootstrap

Scratch template for spinning up a new project with our **standard development
process already wired in** — spec-kit (extensions + presets), the issue↔PR↔milestone
linkage gate, and a stack-agnostic `AGENTS.md`/`CLAUDE.md`.

The stack does not matter. The *process* is the same for every project, so this
repo captures the process once and stamps it into any new project.

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

## Usage

```bash
# 1. scaffold a new project
bash bootstrap.sh ~/code/my-new-project \
  --org myorg/my-new-project \
  --name "My New Project" \
  --tagline "What it is and what is compatibility-sensitive." \
  --git            # optional: git init + first commit
  # --speckit      # optional: also install spec-kit now (needs `specify` CLI)

# 2. fill the {{...}} placeholders above the '---' in AGENTS.md
# 3. create the GitHub repo + first milestone (vX.Y.0)
```

`bootstrap.sh` substitutes `{{PROJECT_NAME}}`, `{{PROJECT_TAGLINE}}`, `{{ORG_REPO}}`
automatically. The remaining `{{...}}` tokens (Role, Stack, Commands, Structure,
Architecture, Test Model, plus `{{BUILD_TEST_CMD}}` / `{{DEP_MANIFEST}}` /
`{{PUBLISH_MECHANISM}}` / `{{RELEASE_NOTES_TOOL}}` in the process section) are left
as TODO for you to fill per stack.

## spec-kit components installed

| kind      | id                    | source                                            | notes |
|-----------|-----------------------|---------------------------------------------------|-------|
| extension | `agent-context`       | catalog (native)                                  | manages CLAUDE.md/AGENTS.md context |
| extension | `bug`                 | catalog (native)                                  | bug triage workflow |
| extension | `git`                 | catalog (native)                                  | feature-branch workflow |
| extension | `worktrees`           | `dango85/spec-kit-worktree-parallel` v1.3.2       | parallel git worktrees |
| extension | `harness`             | `formin/spec-kit-harness` v1.0.0                  | research/verification harness |
| extension | `spectest`            | `Quratulain-bilal/spec-kit-spectest` v1.0.0       | test generation |
| preset    | `claude-ask-questions`| `0xrafasec/spec-kit-preset-claude-ask-questions`  | native AskUserQuestion picker for clarify/checklist |

**Disabled:** `changelog` (`Quratulain-bilal/spec-kit-changelog`) — its `extension.yml`
ships an empty `requires:` block (no `speckit_version`), so `specify` rejects it with
`Validation Error: Missing requires.speckit_version` in every tag and on `main`.
Re-enable in `setup-speckit.sh` once upstream fixes the manifest.

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
