# PC COMMAND protocol v2

PC COMMAND is a lightweight status bus, not a replacement for ChatGPT.

## Goal
Any ChatGPT conversation that the user explicitly asks to connect to **PC COMMAND** should publish a compact workstream state to the shared feed. The local PowerShell viewer reads the feed every 50 seconds.

## Progress model
Each workstream contains tasks with:
- `weight`
- `completion` from 0.0 to 1.0
- `state`: PENDING / ACTIVE / DONE / BLOCKED
- optional `evidence`

Progress is a weighted completion ratio. If new tasks are discovered, the denominator grows and the percentage is recalculated. A temporary drop is therefore valid and means the plan expanded.

The viewer also reports evidence coverage as the reliability of the progress estimate. It must never present the percentage as an exact probability of success.

## Multi-conversation rule
A conversation should:
1. read the latest feed;
2. upsert only its own workstream;
3. preserve all other workstreams;
4. update current_action, last_success, next_step, blocker and task completion;
5. attach evidence whenever a task is marked DONE.

## Local dependency
The viewer only requires:
- PowerShell 5.1+
- Internet access to raw GitHub content.

Desktop Commander is optional for viewing. If it is running, the viewer reports the local connection, but the status feed continues to work without spending Remote Desktop Commander calls.

## UI
- Overview shows all workstreams and progress.
- Keys 1-9 open a workstream.
- A returns to overview.
- R forces a refresh.
- Q closes the viewer.
- Automatic refresh: 50 seconds.
