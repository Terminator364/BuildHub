# PC COMMAND WEB LAB

Status: LAB / PARALLEL / READ-ONLY

## Purpose

PC COMMAND WEB LAB explores a TLIB-like humanized local interface without replacing the stable PowerShell product.

The stable PowerShell app remains the canonical engine and fallback. The web lab is only a presentation/inspection adapter.

## Architecture

```
PC COMMAND stable state
  |-- app/manifest.json
  |-- app/config.default.json
  |-- app/powershell-sources.json
  |-- config/update-status.json
  |-- data/cache/state-sync.json
  |-- state-repo/pc-command/...
             |
             v
Node built-in HTTP adapter
127.0.0.1:8791
             |
             v
Existing browser tab
```

Runtime constraints:
- Node built-ins only.
- No npm runtime dependency.
- No Electron.
- localhost only.
- No Windows service.
- No auto-start.
- No GitHub request in the hot UI path.
- No mutation endpoint in v0.2.
- Canonical state remains PowerShell/GitHub state.
- Browser/API reads are bounded and cache-first.
- server stops after 5 minutes without a request.

## Human surfaces

- Home: stable version, conversations, A+B+C feedback count, PowerShell source count, current/last/next/blocker.
- Conversations: channel state, macro and bounded micro-task detail.
- Health: local RAM, uptime, sync/update, local IPv4 and lab server RAM.
- Local: machine summary and recent generated reports.
- Sources: 41-source PowerShell catalog with local search and classification filters.
- Feedback: recent canonical feedback items with A/B/C expandable detail.
- Versions: recent Version Trace entries and field evidence.
- Technical: raw JSON for maintenance only.

## Field evidence on MBMPC

Observed during the initial field prototype:
- Stable PC COMMAND remained active and unchanged.
- cold start from desktop shortcut: PASS.
- canonical stable detected: v1.0.5/stable.
- feedback index detected: 46.
- PowerShell source catalog detected: 41.
- Node server working set: roughly 41-55 MB during field checks.
- browser delta observed during first lab session: roughly +77 MB compared with the immediately preceding Edge sample.
- combined incremental lab cost while open: roughly 120-135 MB in the first field session.
- this is acceptable for a bounded lab, not yet sufficient evidence for permanent replacement of the low-RAM TUI.

## Promotion policy

WEB LAB must NOT replace the TUI merely because its UX is richer.

Any migration decision requires:
1. no stable PowerShell regression;
2. cold-start and recovery proof;
3. interactive field proof across all main views;
4. measured RAM/latency against the TUI baseline;
5. canonical state parity;
6. explicit action routing through the existing L0-L3 policy layer;
7. rollback to the stable TUI by simply closing the lab.

## Rollback

The lab is isolated under:
`%LOCALAPPDATA%\PC_COMMAND-WEB-LAB`

The stable app remains under:
`%LOCALAPPDATA%\PC_COMMAND`

Closing the browser/lab does not modify stable data. Removing the lab folder/shortcut is sufficient to remove the experiment; stable PC COMMAND remains untouched.
