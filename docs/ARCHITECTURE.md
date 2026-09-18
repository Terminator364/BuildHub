# BuildHub architecture

## Trust boundary

BuildHub public contains only generic orchestration logic. Product repositories remain private and inject their build commands, paths, and credentials at runtime.

## Execution model

1. **Doctor** records environment capability before work starts.
2. A build operation receives a unique operation ID.
3. Heavy-build parallelism defaults to one on constrained local systems.
4. Progress is observable through machine-readable heartbeat and durable receipts.
5. Recovery state is idempotent and rejects replay of committed steps.
6. Publication is staged to a temporary path.
7. SHA-256 is checked before replacement.
8. Destination readback is hashed after replacement.
9. Only then may a receipt become **COMMITTED**.

## GitHub versus local PC

Public GitHub CI is a validation and acceleration layer. It must not become a hard dependency for local use. The Windows runtime is designed toward cache-first/offline-capable operation and bounded resource use.

## Historical regression obligations

The following mechanisms from BUILD1/BUILD2 are permanent test obligations:

- argument handling for 0 / 1 / N inputs and paths containing spaces;
- missing payload/module imports;
- false COMMITTED state without output hash/readback;
- stale recovery replay;
- UTF-8 BOM JSON;
- insufficient heartbeat on long-running work;
- idempotence;
- partial publication;
- cancellation propagation, including externally interrupted Windows processes;
- CI quota/external-service exhaustion must not corrupt local state.

These mechanisms belong in the error ledger and should become executable regressions rather than narrative-only lessons.
