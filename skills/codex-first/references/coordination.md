# Coordination and verification

Read when coordinating workers or verifying their output.

## Coordinator verification (beyond the diff)

Worker reports are accurate but incomplete — pathologies live in the code, not the summary.
After every landed PR, verify against merged origin/main, not the report:

- read the actual merged surface (types, interfaces, naming) — the minification incident was
  invisible in a green report and obvious in 10 lines of code
- squash history: any commit message you didn't commission ("add startup margin") is a lead
- diff-stat the guard/budget/baseline files the spec forbade touching; if a limit number in the
  report changed, find out who moved it (may be main advancing, may be the worker)
- test-helper edits are a red-flag class of their own (defineProperty shims re-exposing moved
  fields keep suites green while hiding the migration)

## Parallel workers, one repo

Disjoint-file tasks parallelize cleanly: one worktree + unique branch per worker (fresh from
origin/main; distinctive branch names — generic ones attach to old PRs), one tracked background
command each, shared spec body + per-target header. Landing serializes on the repo's land
workflow lock: tell each worker a held lock means a sibling owns it — back off 5-10 min, retry
from the failed step, NEVER lock-recover a lock it didn't create, and don't chase main with
fresh gates as siblings land under it. Sequential series instead reuse ONE worktree, rebranching
from origin/main per PR.

## Verify (Claude, always)

- `git status -sb` + read the full diff; judge like a contributor PR
- run focused tests yourself or demand proof output; Codex claims are advisory
- iterate via resume; after 2 failed rounds, take over and do it directly
- normal closeout still applies: `$autoreview` before ship
- **check for a live worker in the repo before you edit or commit**:
  `pgrep -fl "codex exec"`. A run whose deliverable is already in the tree can
  keep looping for hours and overwrite your fixes mid-review. Stop it once you
  have verified its output rather than racing it.
- a genuinely independent review pass earns its keep: reviewing the working tree
  after a Codex build found a currency value being fed to a percentage helper
  that clamped at 100, which typechecked, passed every test, and was invisible in
  the worker's own report.

## Economics

Win = generation + exploration tokens moved to Codex; Claude spends only on spec + diff review. Don't ping-pong trivia through delegation; don't re-read what Codex already summarized.
