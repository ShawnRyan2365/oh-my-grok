# oh-my-grok

A **hardened, self-built fork of [Grok Build](https://github.com/xai-org/grok-build)** — SpaceXAI's terminal AI coding agent.

> Build it yourself. Run the binary you built. No silent uploads, no silent
> self-updates, no server-side switch that can flip data collection back on.

In July 2026 Grok Build was caught uploading users' repositories, Git
histories, SSH keys, and password databases to cloud storage — even when told
not to open files. xAI open-sourced the code shortly after and removed the
explicit "codebase upload" path, **but the upload pipeline that carried it is
still in the tree**, and its on/off switch is one a remote server can flip.

`oh-my-grok` is that pipeline, hard-disabled at the source, plus a frozen
build that won't replace itself. Every change is a small, readable guard you
can audit in [`HARDENING.md`](HARDENING.md).

---

## What's different from upstream

Three surgical patches (+35 lines across 4 files). Each hard-disables one
egress path regardless of server settings, config, or requirement pins.

| Patch | File | Effect |
|-------|------|--------|
| Telemetry + trace uploads forced off | `xai-grok-shell/src/agent/config.rs` | No per-turn trace bundles (conversation, config, memory, logs) leave the machine |
| Auth diagnostics upload suppressed | `xai-grok-shell/src/upload/gcs.rs` | Auth-failure logs stay local |
| Auto-update disabled | `xai-grok-update/src/auto_update.rs` | The binary never silently downloads/replaces itself |

The binary is also renamed `grok` → **`oh-my-grok`** so you can tell at a
glance which build you're running (`oh-my-grok --version`).

Full audit, rationale, and re-audit commands: **[`HARDENING.md`](HARDENING.md)**.

## What this does **not** change

- **It is still a cloud coding agent.** File content you reference is sent to
  the xAI inference API as prompt context — that's inherent to using a hosted
  model. "No telemetry" ≠ "no data leaves the machine." For zero egress, point
  it at a local model.
- **Config paths are unchanged** (`~/.grok`, `ai.x.grok`, `GROK_*` env vars)
  for ecosystem compatibility. Renaming those would orphan your auth/settings.
- Functionality, the TUI, tools, and skills are otherwise identical to upstream.

## Build

Requirements: **Rust** (pinned by [`rust-toolchain.toml`](rust-toolchain.toml);
`rustup` auto-installs it) and **protoc**.

```sh
git clone https://github.com/ShawnRyan2365/oh-my-grok.git
cd oh-my-grok

# protoc: either install DotSlash (upstream's path) or point at a system protoc
export PROTOC="$(command -v protoc)"   # e.g. brew install protobuf

cargo build -p xai-grok-pager-bin --release
# → target/release/oh-my-grok
```

Install it on your `PATH`:

```sh
install -m 755 target/release/oh-my-grok /usr/local/bin/oh-my-grok
oh-my-grok --version    # oh-my-grok 0.2.106 (<commit>)
```

> [!IMPORTANT]
> Do **not** use the upstream `curl … x.ai/cli/install.sh` path — that fetches
> a prebuilt binary you cannot match to this source. The whole point is that
> you build and run the same bytes you audited.

## Defense in depth

Client-side patches can't stop a server-driven config change from re-arming a
path. Pair this fork with a **network firewall** that allows egress only to the
inference API host you use. See [`HARDENING.md`](HARDENING.md#defense-in-depth-recommended-not-patched).

## Syncing upstream

`upstream` tracks xAI; `origin` is this fork.

```sh
git fetch upstream
git merge upstream/main      # then re-audit the egress paths (see HARDENING.md)
```

Always re-run the re-audit greps after a sync — upstream may add a new egress
path or change the gating logic.

## Documentation

The upstream user guide ships with the pager crate at
[`crates/codegen/xai-grok-pager/docs/user-guide/`](crates/codegen/xai-grok-pager/docs/user-guide/)
— getting started, keyboard shortcuts, slash commands, configuration, MCP
servers, skills, plugins, hooks, headless mode, sandboxing.

Original upstream README: [`README.upstream.md`](README.upstream.md).

## Status

Early. The hardening is done and the build is verified, but this is a personal
hardened fork — **audit it yourself before use**, and do not run it on
machines holding material you cannot afford to expose until you have.

## Disclaimer

Not affiliated with, endorsed by, or representative of xAI or SpaceXAI. "Grok"
and "Grok Build" are their marks; this project uses them only to describe what
the code is a fork of. All first-party code remains Apache-2.0 (see
[`LICENSE`](LICENSE)); third-party notices apply (see
[`THIRD-PARTY-NOTICES`](THIRD-PARTY-NOTICES)).
