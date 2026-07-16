# autobuild-pipeline

> **Take the human out of the courier seat — keep them on the gates.**

An autonomous **build-to-mergeable** pipeline for [Claude Code](https://claude.com/claude-code):
pick a bounded, testable task from a backlog → a headless architect/engineer loop builds it in an
isolated git worktree, self-reviews, and **stops at a ready-to-push branch** for a human to approve.
The point is to take the human out of the *courier* seat (pasting between agent turns) while keeping
them firmly on the *gates* (push, merge/deploy, runtime verification).

Model-tiered, budget-capped, worktree-isolated. It never pushes, merges, or deploys on its own.

## How it works

```
triage        classify the backlog → buildable task specs vs "needs a human"
   │
run-task      per task, in an isolated git worktree off main:
   │            1. plan     (capable model)   → PLAN.md         (plan only, no code)
   │            2. build    (implementer)     → code + commit    (+ verification-before-completion skill)
   │            3. review   (capable model)   → REVIEW.md        (independent; runs the verify itself)
   │            4. fix      (implementer)     → fixes            (only if review = CHANGES REQUIRED)
   │          then an independent verify (install + typecheck + test + build; count must match baseline)
   ▼
STOP at "ready to push"   ← never pushes / merges / deploys
```

`dispatch.sh` runs a whole batch of buildable tasks under a budget cap and logs each outcome.

**Model tiering is deliberate and pinned per stage** (never inherited from the session default):
a capable model plans and reviews; a cheaper implementer model builds and fixes. Confirm it held via
each run's `modelUsage` in the result JSON.

## Quickstart

Requires: `claude` CLI (Claude Code), `git`, `python3`, and your project's toolchain.

```bash
cp config.example.json config.json      # point it at your repo(s)
# optional: hand-author tasks in tasks/<project>.json (see tasks/*.example.json)
./triage.sh <project>                    # or author tasks yourself
BUDGET_CAP=20 ./run-task.sh <project> <task-id>     # one task
BUDGET_CAP=20 MAX_TASKS=4 ./dispatch.sh <project>   # a batch
```

Config per project (`config.json`): `repo` (checkout path), `remote` (for the eventual PR),
`package_manager`, `verify` (the full install+typecheck+test+build command), `test_pass_regex`
(captures the passing-test count from `verify`), `backlog` (repo-relative task source for triage).

Tune with env: `BUDGET_CAP`, `MAX_TASKS`, `AUTOBUILD_WORKROOT`, `AUTOBUILD_CONFIG`, `CLAUDE_BIN`,
`AUTOBUILD_MODEL_PLAN`, `AUTOBUILD_MODEL_BUILD`, `AUTOBUILD_MODEL_TRIAGE`.

## The human gates (never automated)

1. **Push → draft PR** — after you've reviewed the branch:
   `git -C <repo> push -u origin loop/<id>` then `gh pr create --draft ...`. PRs are drafts; never auto-merge.
2. **Merge / deploy** — always a human action.
3. **Runtime / UI verification** — what tests can't see (framework boot, a renamed dependency export, a
   rendered UI) is verified by a human before merge. *Don't trust green tests* for those surfaces.

## Deploy & preview are YOUR interfaces (not shipped)

This tool intentionally stops at a mergeable branch. Deploy and preview are environment-specific, so
they're **hooks you wire yourself** — nothing about any real infrastructure ships here.

- **Deploy**: after merge, run your own deploy (e.g. `docker compose build && docker compose up -d`,
  a CI pipeline, a PaaS push). Recommended discipline: integrate change(s) → *re-verify the combination*
  (individually-green ≠ combined-green) → tag/note the current release for rollback → deploy →
  health-check yourself → roll back instantly if off.
- **Preview** (optional, for changes tests can't cover): stand up an *ephemeral* copy of your app with a
  throwaway database and a non-production config to smoke a branch before merge. If your app needs auth,
  inject a session at the **preview layer** (a proxy/sidecar), never by adding a bypass to your
  application code — so the bypass cannot exist in production. Keep previews private (e.g. VPN-only).

## Safety

This drives an autonomous coding agent that edits files and runs commands in a worktree. Review its
output. Start with `BUDGET_CAP` low. The independent-verify step and the human gates are load-bearing —
don't remove them.

## License

Everything here is original. MIT — see [LICENSE](LICENSE). No warranty.

- For **difficult / high-stakes builds** where you want a human checkpoint at *every* stage (not just the
  gates), see its sibling [handoff-loop](https://github.com/itcodingtech/handoff-loop).
