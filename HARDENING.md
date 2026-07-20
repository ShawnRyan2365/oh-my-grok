# oh-my-grok Hardening

A hardened fork of [xai-org/grok-build](https://github.com/xai-org/grok-build).

This document records **exactly** what data egress exists in the upstream
binary and **exactly** what this fork changed to neutralize it. Every change
is small, localized, and reverts trivially — read the diff alongside this
file and re-audit before trusting it.

## Why

In July 2026, researchers found that Grok Build was uploading user
repositories — full Git histories, SSH keys, and password-manager databases —
to cloud storage, even when instructed not to open files. xAI open-sourced the
code shortly after; the explicit "codebase upload" path has since been removed
from the tree. **But the upload pipeline that carried it is still present.**

The remaining concern: the per-turn trace-upload pipeline and telemetry stream
are gated by a resolution chain in which **xAI's server-side remote settings
can re-enable collection**, and the default binary is a prebuilt artifact you
cannot match to source. This fork closes both gaps.

## What still exfiltrates in upstream (audit, current `main`)

| # | Path | Payload | Gate |
|---|------|---------|------|
| 1 | `xai-grok-shell/src/upload/{trace,turn,manifest,gcs}.rs` + `xai-file-utils/src/queue.rs` | Per-turn trace bundle: full conversation (`turn_messages.json`), your config (`config.json`), permission decisions, `memory.tar.gz` (memory + session logs), unified logs, model reasoning captures | Server-overridable |
| 2 | `xai-grok-shell/src/upload/gcs.rs` `upload_to_auth_diagnostics` | Auth-failure logs (user id, version, error detail) → `auth-diagnostics/` | Triggered on 401 / refresh failure |
| 3 | `xai-grok-telemetry/src/external/` | OTLP event stream; prompt text and tool params under `OTEL_LOG_USER_PROMPTS` / `OTEL_LOG_TOOL_DETAILS` | Follows telemetry mode |
| 4 | `xai-computer-hub-sdk/src/log_donate.rs` | Allowlisted tracing events over the workspace-server WebSocket | After workspace-server connect |
| 5 | `xai-grok-update/src/auto_update.rs` | Version check + download of new binaries from x.ai | Default on |

Gate resolution for #1/#3 (`agent/config.rs`):
`requirement pin → env var → config.toml → server remote_settings → default`.
The server sits before the default, so with no local override it can flip
collection on. (Items #4 and #6 share, session-share, are user-initiated and
are not treated as exfiltration.)

## What this fork changes

Three surgical patches. Each hard-disables a path regardless of server
settings, requirement pins, or local config.

### Patch 1 — telemetry + trace upload forced off
`crates/codegen/xai-grok-shell/src/agent/config.rs`

- `resolve_telemetry_mode()` → unconditionally `TelemetryMode::Disabled`
- `resolve_trace_upload()` → unconditionally `false`

Kills #1 and #3 at the root. The original bodies are left in place (unreachable)
so the diff is a one-line guard you can eyeball; revert by deleting the guard.

### Patch 2 — auth diagnostics never uploaded
`crates/codegen/xai-grok-shell/src/upload/gcs.rs`

- `upload_to_auth_diagnostics()` → returns immediately, logs locally only.

Kills #2.

### Patch 3 — auto-update disabled
`crates/codegen/xai-grok-update/src/auto_update.rs`

- `auto_update_target()` → `None`
- `run_update_if_available()` → `Ok(false)`
- `check_update_background()` → `BackgroundUpdateCheck::none()`

Kills #5. The binary you build is the binary you run; it will not silently
replace itself with an unaudited build. Explicit `grok update` still works.

## Defense in depth (recommended, not patched)

- **Network firewall.** Allow egress only to the inference API host you
  actually use. Client-side patches can't stop a server-driven config from
  re-arming a path; a firewall can. This fork assumes you pair it with one.
- **Environment variables.** Belt-and-suspenders: set
  `GROK_TELEMETRY_ENABLED=off` and `GROK_TELEMETRY_TRACE_UPLOAD=0`. In
  upstream these already override the server; here they are redundant.

## What this fork does NOT change

- It is still a cloud coding agent. File content you reference is sent to the
  inference API as prompt context — that is inherent to using a hosted model.
  "No telemetry/upload" ≠ "no data leaves the machine." For zero egress, run a
  local model.
- The command/binary is `omg` (project: oh-my-grok; upstream: `grok`). Internal
  brand identifiers and config paths (`~/.grok`, `ai.x.grok`, `GROK_*`) are
  unchanged.
- `bin/protoc`, `third_party/`, and the tool implementations (codex/opencode
  ports) are untouched.

## Re-auditing

```bash
# Confirm no upload path re-armed since this doc was written:
rg -n "is_trace_upload_enabled|resolve_trace_upload|upload_to_auth_diagnostics" \
   crates/codegen/xai-grok-shell/src
rg -n "auto_update_target|check_update_background|run_update_if_available" \
   crates/codegen/xai-grok-update/src
```

Not affiliated with xAI or SpaceXAI. Audit it yourself before use.
