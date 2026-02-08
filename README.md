# CodexMonitor (Velox Port)

![CodexMonitor](screenshot.png)

CodexMonitor is a macOS desktop app for orchestrating multiple Codex agents across local workspaces.

This is a Swift/Velox port of the Tauri/Rust app from
[Dimillian/CodexMonitor](https://github.com/Dimillian/CodexMonitor),
ported at commit [`cab9dde`](https://github.com/Dimillian/CodexMonitor/commit/cab9dde535afa99ccfb079377a455ff435e5a55d)
(chore: bump version to 0.7.45).

## What It Does

- Manage multiple local workspaces and spawn one Codex app-server per workspace.
- Restore and resume past threads per workspace.
- Chat with agents, stream tool output, and handle approvals.
- Create and delete worktrees for parallel agent sessions.
- Browse git status, diffs, and logs per workspace.
- Track model usage, rate limits, and per-turn plans.

## Project Setup

This repository (`sample-codex-monitor`) expects the CodexMonitor frontend
source to live alongside the `velox-app/` directory. Clone both repositories
into the same parent folder:

```bash
git clone https://github.com/Dimillian/CodexMonitor
git clone https://github.com/<you>/sample-codex-monitor velox-app
```

Resulting layout:

```
CodexMonitor/          Frontend source (React + Vite) — cloned from upstream
velox-app/             Swift backend + Velox config (this repo)
velox-app/frontend/    Built frontend assets copied during build
velox/                 Velox runtime (Swift build tool)
```

## Requirements

- Node.js + npm
- Xcode or Swift toolchain
- Velox CLI
- Codex CLI available as `codex` in `PATH`
- Git CLI

## Build and Run

Install frontend dependencies once:

```bash
cd CodexMonitor && npm install
```

Build the Velox runtime once (avoids SwiftPM sandbox issues):

```bash
cd velox && make
```

### Makefile targets

From the `velox-app/` directory:

| Target | Description |
|--------|-------------|
| `make dev` | Start Vite dev server and Swift backend together |
| `make build` | Build the frontend and Swift binary (release) |
| `make bundle` | Build the frontend, Swift binary, .app bundle, and DMG |
| `make run` | Build everything, clear quarantine, and launch the app |
| `make clean` | Remove build artifacts |

Quick start:

```bash
cd velox-app
make run
```

To run from the terminal with log output instead of `open`:

```bash
cd velox-app
make bundle
.build/release/CodexMonitor.app/Contents/MacOS/CodexMonitor
```

The app is not code-signed by default. `make run` clears the quarantine
attribute automatically. If you launch manually, use
`xattr -cr .build/release/CodexMonitor.app` first or right-click and choose Open.

## Using the App

1. Add a workspace from the sidebar.
2. Wait for the workspace to connect to Codex.
3. Start a thread, send messages, and review responses.
4. Use the git panel and worktree actions as needed.
5. Archive or delete threads and workspaces when you are done.

## Credits

This is a Swift/Velox port of [CodexMonitor](https://github.com/Dimillian/CodexMonitor) by [@Dimillian](https://github.com/Dimillian).
