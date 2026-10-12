# Worker and route troubleshooting

Read after a failed launch or before changing provider settings.

## When the worker dies instantly

A run that exits in seconds having produced nothing is almost never the task —
it is the model route. Read the log tail before relaunching; the error names the
cause, and relaunching unchanged just repeats it:

- `401 Invalid API key` — the configured bearer is not valid at that endpoint.
- `502 / All target providers failed` with a `target_providers` list — the
  request reached a router but the **model id did not match its catalogue**, so
  it fell through to the wrong upstream. Routers commonly expose aliased model
  ids that differ from the underlying model's real name; pass the id the router
  publishes, not the one you think you are using.
- `stream disconnected` / `Reconnecting… 5/5` against a loopback URL — nothing
  is listening there.
- `requires a sandbox with reviewed escalations` — `--yolo` is unsupported for
  that route. Retry once with `--approve-for-me`, which selects workspace-write,
  on-request approvals, and automatic review.

Diagnose the route directly rather than by retrying the agent. One request
settles it, and it is far cheaper than another failed run:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -m 8 <base_url>/models
```

A local config pointing at a loopback port proves nothing about that port being
served: config files outlive the services they were written for, and a
machine-managed provider block can reference an instance that no longer runs.
Check what is actually listening before trusting it.

**Never pass a credential through `-c key=value`** — it lands in argv, process
listings, and shell history. When a run needs different provider settings,
write a private overlay instead and point `CODEX_HOME` at it: a mode-0700
directory holding a mode-0600 `config.toml` (copy `auth.json` across if the
provider needs it). That keeps the secret in a file, leaves the user's global
config untouched, and is trivially disposable.

If the environment's own Codex config is broken, say so rather than silently
working around it every invocation — the next task will hit the same wall.
