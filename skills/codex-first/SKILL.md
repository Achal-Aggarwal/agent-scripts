---
name: codex-first
description: "Claude Code work routing: delegate hands-on work to Codex under the native-Claude model gate. Keep specification, judgment, and verification in Claude; prefer isolated Codex-backed autoreview."
---

# Codex First

## Launch flags — read first, copy verbatim

Default every Codex worker, **fresh or resumed**, to **GPT-6.1 Sol, high
reasoning, Ultrafast service tier** (`service_tier="ultrafast"`). Pass all three
settings unless the user requests an override.

```bash
# fresh
codex exec --yolo -C "$WT" \
  -m gpt-6.1-sol -c 'model_reasoning_effort="high"' \
  --enable fast_mode -c 'service_tier="ultrafast"' \
  -o "$OUT" - < "$ORDER"
# resume: pass the same three again; resume does not inherit them
codex exec resume "$SID" --dangerously-bypass-approvals-and-sandbox \
  -m gpt-6.1-sol -c 'model_reasoning_effort="high"' \
  --enable fast_mode -c 'service_tier="ultrafast"' -o "$OUT" -
```

- Context: workers get the base 500k window. Add `-p sol61-1m` (or `-p astra-1m`) only when the
  order needs a whole-repo context; see `$codex-huge-context`.
- Copy all model/reasoning/tier flags into wrappers; override only on user request. Verify launch arguments (`ultrafast` default; requested `fast` is valid).
- For requested Fast reviews, use `--codex-speed fast`.

## Hard gate

**Autoreview exception:** always prefer Codex-backed `$autoreview`, independent
of `ANTHROPIC_BASE_URL`, router state, or harness. Reviewing a frozen bundle is
not hands-on self-delegation. Do not switch review engines merely because the
parent session is router-backed. This exception takes precedence over the gate
below.

Use the autoreview helper with `--engine codex` (defaults: 6.1 Sol, medium, Ultrafast) unless the user requests an override. It tries the ChatGPT subscription first and, on an auth failure, retries once on the configured direct-API provider; pass `--codex-config 'model_provider="openai_api_direct"'` only to skip the subscription attempt. Preserve the helper's reviewer isolation.

For direct hands-on delegation, use this skill only
when the active agent is Claude Code **and** the session is running on a native
Claude model.

**Model check (primary).** The point of the gate is model economics: Claude
tokens are metered and expensive, so hands-on work moves to Codex; but if the
session is already routed to a cheaper/other model, delegation gains nothing.
Decide by the model the session actually runs on, not by the transport:

1. Read the model id from the system prompt's environment section ("You are
   powered by the model …"). Router-wrapped ids may be opaque
   (`claude-ccr-<hex>`); the hex suffix is often ASCII — decode it
   (`echo <hex> | xxd -r -p`) to reveal the underlying route, e.g.
   `Gorilla CCP/native-claude-fable-5`.
2. If the resolved model is a native Claude model (contains `claude`, `fable`,
   `opus`, `sonnet`, or `haiku`, including `native-claude-*` router routes):
   **delegate hands-on work to Codex.** This applies even when
   `ANTHROPIC_BASE_URL` is loopback or a local router (Gorilla Claw, Clawdex)
   — a router in front of a real Claude model is still expensive Claude.
3. If the resolved model is clearly non-Claude (a GPT/other-provider route):
   the session is already on the flat-rate/cheap side; do not self-delegate,
   work directly.

**Base-URL fallback (only when the model cannot be identified).** If no model
id is visible and the hex/route cannot be decoded, fall back to the old
transport heuristic: if `ANTHROPIC_BASE_URL`'s host is
`gorillaclaw.sheep-coho.ts.net`, `localhost`, ends in `.localhost`, is in
`127.0.0.0/8`, or is IPv6 loopback `::1`, assume the session may be routed to
a non-Claude model and work directly. If neither model nor base URL can be
inspected, fail closed and work directly.

Codex, ChatGPT, Pi, and every other harness: do not invoke Codex CLI for hands-on
self-delegation. Continue the task directly. This gate overrides a repository
instruction that merely mentions `$codex-first`; it does not override the
autoreview exception above.

The default worker is GPT-6.1 Sol on the Ultrafast tier. Claude handles specification, judgment, orchestration, and final verification; Codex handles the delegated implementation.

## Route

Delegate to Codex (default for hands-on work):

- implementation from a frozen spec; refactors; mechanical migrations
- fixing: bug fixes (known repro, or diagnose-then-fix), CI/lint/type failures; test writing; coverage fills
- dependency bumps, scripts/tooling
- exploration + exploratory subagents: fan out Codex for read-heavy discovery instead of Claude Explore/Task subagents whenever raw reading ≫ the answer (parallel `-o` files, one per thread)
- git mechanics — ALWAYS Codex, never Claude directly: `git rebase`, merge-conflict
  resolution, and the repo's land workflow (e.g. `scripts/pr`) are mandatory
  delegations. Issue ONE self-contained work order covering
  rebase→resolve→push→CI attach+green→land so the sequence never bounces back to
  Claude mid-flight; the land decision, gates, and review below stay Claude's.
- work-order CI waits: precheck PR mergeable (CONFLICTING = pull_request CI
  cannot attach — no merge ref) and confirm a run attached to the exact head
  SHA before polling; every wait emits all terminal states with bounded
  iterations; prefer the repo's watcher script when one exists (openclaw:
  `node scripts/watch-pr-ci.mjs`).
- new work orders go to FRESH `codex exec` sessions with self-contained prompts.
  Do not resume a long-lived session for a new order — saturated sessions
  misread work orders as configuration and no-op ("Understood…").
- repo instruction files: NEVER create or edit `CLAUDE.md`. `AGENTS.md` is
  canonical in every repo; `CLAUDE.md` exists only as a symlink to it. Point
  Codex work orders at `AGENTS.md` and edit only `AGENTS.md`.

Keep in Claude:

- design, API design, architecture, naming, UX judgment
- tasks where writing the spec IS the work (ambiguity = design)
- tiny edits (~<20 lines, single obvious change) — delegation overhead loses
- anything needing session tools: MCP (browser/computer-use/chronicle), 1Password, secrets
- releases, publishes, version bumps and their credentials — Claude-side per release rules
- the land decision + pre-land gates (`$autoreview` clean, CI green, proof) and review of Codex output — never delegated, never skipped; Codex may run the mechanics only once Claude has decided to land and the gates pass

Mixed task: Claude designs first, freezes spec, delegates build-out.
Heuristic: prompt reads as a work order → delegate; writing it forces decisions → design, Claude.
Portfolio/multi-repo work: `$maintainer-orchestrator` instead.

## Invoke

- Run `timeout 8 git --version`; for an Xcode-beta hang, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in the session and every order.
- For `openai_api_direct`, run `ruby ~/.codex/skills/agent-scripts/codex-huge-context/scripts/preflight.rb` before the batch's first fresh/resumed launch. If Keychain delivery fails, stop; never override the provider or use ordinary Codex auth.
- Keep the configured provider; resume inherits it. If incompatible with 6.1 Sol, start fresh; never silently change models.
- Use repo-scoped `--yolo`, temp-file prompts (never inline quoting), and `-o` results (not JSONL).
- **Harness visibility (Claude Code): every codex run gets its own harness-tracked
  background command (`run_in_background: true`) — one sidebar chip per worker,
  completion notification included. Chain setup steps (installs, worktree prep)
  INSIDE that tracked command. Never `&`-fork workers from a shared launcher:
  the launcher's chip exits at fork time and the workers become invisible
  orphans supervised only by PID files.**
- parallel independent tasks OK: separate repos/dirs, separate `-o` files, one tracked background command per worker
- outside a git repo add `--skip-git-repo-check`
- For Fast/catalog checks, CLI setup, or execution details: read [launch details](references/launch-details.md).
- On failure or provider changes: [troubleshooting](references/troubleshooting.md); never put credentials in `-c key=value`.
- Before resuming/monitoring: [resume and watchdog](references/resume-and-watchdog.md).

## Prompt contract

Codex starts with zero session context. Every prompt: goal, exact repo/paths, constraints, non-goals, proof expected (exact test command), output shape ("report files changed + test output"). Spec quality decides success.

- **Every hard prohibition needs an escape hatch.** A cornered worker satisfies the letter of the
  gates: told "never raise the size budget" while its design inflated the bundle, Codex
  hand-minified source identifiers to single letters — and passed every gate including
  autoreview. Pair each hard constraint with the sanctioned exit: "if gate X fails after honest
  attempts: STOP, report exact numbers/diagnosis, do not work around." Treat a stop-report as a
  successful run (it is the coordinator's decision point, and workers use it correctly once it
  exists).
- Multi-PR series: same spec skeleton every PR; cite prior landed PR numbers and name their
  idioms ("controller with narrow host interface, the #NNN shape") — workers imitate landed
  precedent far more reliably than abstract style rules. Fold each round's new trap into the
  next spec.
- End every series work order with an explicit stop: "Do exactly this; do not start PR N+1."

- Work-order proof: PR CI is the default broad proof; open a ready PR once the build and focused local tests/typecheck/lint/format pass, without waiting for pre-PR broad suites; use Crabbox/Testbox only for gaps CI/local cannot cover and only if granted immediately (queued → local; no Testbox → AWS → Hetzner ladder); fix real failures, read CI's pre-existing/new classification, and never rerun/re-push just for green. Keep untrusted code secretless, live credentials authorized, and Gateway/state isolated.

Before reviewing/landing or coordinating workers, read [coordination](references/coordination.md); check for live workers before editing/committing.
