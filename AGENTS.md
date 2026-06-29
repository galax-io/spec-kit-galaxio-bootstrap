# spec-kit-galaxio-bootstrap — Agent Guide

Copier template that stamps Galaxio's standard dev process — spec-kit, the issue↔PR↔milestone linkage gate, and a stack-agnostic AGENTS.md/CLAUDE.md — into any new project.

> The sections above the `---` are **project-specific** — fill them in for each new
> project. Everything below the `---` is the **stack-agnostic development process**
> and is meant to be reused verbatim across all projects.

## Role

Maintainer of a stack-agnostic Copier project template. Prefer minimal, reversible
changes; keep generated output stable across every stack; never re-implement the
linkage-gate scripts or setup-speckit.sh — they are copied verbatim.

## Stack

Copier (Jinja2 templates) + bash. No compiled artifact — the deliverable is
`template/` rendered by `copier.yml`. Tooling: the `copier` CLI and `bash -n`.

## Commands

```bash
# lint    bash -n setup-speckit.sh scripts/check-linkage.sh .claude/hooks/linkage-guard.sh
# smoke   copier copy --trust --pretend --defaults --data project_name=X --data org_repo=o/r . /tmp/out
# update  copier update --trust          # run inside a generated project
# speckit bash setup-speckit.sh          # install spec-kit extensions/presets
```

## Structure

- `copier.yml` — questions, stack-driven Jinja defaults, post-gen tasks
- `template/` — render root (`_subdirectory`); `.jinja` files + verbatim scripts/hooks + per-stack stubs
- `scripts/check-linkage.sh`, `.claude/hooks/linkage-guard.sh`, `setup-speckit.sh` — the verbatim sources
- `README.md` — Copier usage + spec-kit component table + gotchas

## Architecture

`copier.yml` defines the questions and Jinja defaults; `_subdirectory: template` is the
render root. AGENTS.md/CLAUDE.md/.gitignore are templated; the linkage gate
(`scripts/check-linkage.sh` + `.claude/hooks/linkage-guard.sh`) and `setup-speckit.sh`
are copied byte-for-byte — never re-implemented. `.copier-answers.yml` records the
answers so `copier update` can re-apply later template changes without clobbering edits.

## Test Model

No unit tests. Validation = generate across every stack and assert no stray `{{ }}`,
`bash -n` on all shell scripts, byte-equivalence of the verbatim files, and a
`copier update` round-trip that preserves user edits.

---

<!-- ===================================================================== -->
<!-- STACK-AGNOSTIC DEVELOPMENT PROCESS — reuse verbatim across projects.   -->
<!-- ===================================================================== -->

## Boundaries

**Always:** format before commit, branch from `main`, keep commits semantic and green, preserve backward compat for published public APIs and any downstream consumers. `copier.yml` = dependency truth, `.github/workflows/` = CI/release truth.

**Ask first:** new deps or upgrades, changing public API signatures / observable behavior / serialized formats, editing another repo, release/publish workflow changes.

**Never:** force-push or commit to `main`, merge commits in PR branches (rebase only), commit broken code, opportunistic refactors outside scope, mock external systems where a real integration path exists.

## Milestones (ALWAYS)

Every piece of work is tied to a milestone. No exceptions unless explicitly told otherwise.

- **Every PR** must be assigned to the active milestone before merging. No milestone = do not merge.
- **Every issue** fixed by a PR must be closed when that PR lands on `main`. Do not leave completed issues open.
- **Spec work** (`specs/NNN-*/`) belongs to the milestone that owns the spec. Link the spec PR to the milestone immediately when creating it.
- **Active milestone** = the lowest-numbered open milestone that matches the current spec/plan. Check `gh api repos/galax-io/spec-kit-galaxio-bootstrap/milestones` if unsure.

## Commits & PRs

- **Spec-first.** `specs/NNN-*/` artifacts → `docs(speckit): add NNN-<feature> spec/plan/tasks` commit BEFORE any `feat`/`fix`. Never folded into implementation.
- **1 issue = 1 commit.** Each tracked GitHub issue maps to one semantic commit (`feat(scope): … (#NNN)`), green on its own (`bash -n setup-speckit.sh scripts/check-linkage.sh .claude/hooks/linkage-guard.sh`). Docs, tweaks, and out-of-scope improvements go in separate PRs — never mixed with issue commits.
- **Intent, not path.** No add-then-remove within a PR. Squash churn before review.
- **1 concern per PR.** Feature ≠ docs/README. Stack dependent PRs; update with `--force-with-lease`.
- **Idiomatic code.** Follow the language's idioms and the conventions already in the codebase; no control-flow-by-exception, no dead/duplicated code.

## Release Process (MANDATORY)

Trunk-based with release branches. Trunk is `main`; `release/*` branches are cut from `main` for stabilization. Pushing a `vX.Y.Z` tag on `main` or a `release/*` branch triggers the release workflow (git tag vX.Y.Z, consumed via copier copy/update gh:galax-io/spec-kit-galaxio-bootstrap) and creates a GitHub Release (manual GitHub Release).

### Minor/Major release (e.g. 1.2.0, 2.0.0)

1. `git checkout -b release/X.Y.0 main` — cut release branch from `main`
2. `git push -u origin release/X.Y.0`
3. `git tag vX.Y.0` on the release branch
4. `git push origin vX.Y.0` — triggers release workflow

### Patch release (e.g. 1.2.1)

1. Fix lands on `main` first (via PR as usual)
2. `git cherry-pick <fix-sha>` onto `release/X.Y.0`
3. `git tag vX.Y.1` on the release branch
4. `git push origin vX.Y.1` — triggers release workflow

### Rules

- **Every minor version gets its own `release/X.Y.0` branch** — no exceptions
- **Tags ONLY on `release/*` branches or `main`** — `release.yml` validates this
- **Branch name must match tag version**: `release/1.2.0` → `v1.2.0`, `v1.2.1`, etc.
- **Never delete a release tag** after the registry deployment starts — creates stuck deployments
- **Never reuse a version number** — most package registries reject duplicates permanently
- **Before tagging**: every PR merged since the previous tag must be assigned to the milestone; every issue in the milestone whose fix is on `main` must be closed

<!-- The issue↔PR↔milestone contract above is enforced mechanically by         -->
<!-- scripts/check-linkage.sh + the .claude/hooks/linkage-guard.sh PreToolUse   -->
<!-- hook (gates release tagging only; normal push/PR/merge untouched).         -->
