# BuildHub Generic WebView Shell

A deliberately small Win32 + WebView2 shell built by the public BuildHub CI.

It is **generic infrastructure**, not a product repository. Product identity and homepage are supplied at runtime by an adjacent INI file. This keeps private product source/configuration outside the public BuildHub repository while still allowing the generic engine to be compiled and hardened with public CI.

## Current bootstrap invariants

- Windows x64 native C++20 / Win32 host.
- Microsoft Edge WebView2 Evergreen runtime.
- One physical WebView2 controller in the bootstrap build (within the architectural ceiling of two).
- Up to three logical tabs; switching a logical tab navigates the single physical slot.
- Local state under `%LOCALAPPDATA%/<app_id>`.
- WebView2 user data under `%LOCALAPPDATA%/<app_id>/WebView2`.
- No cloud telemetry, extensions, resident AI, or automatic updater.
- Runtime version change is recorded locally.
- Low-memory Windows notification is registered; the bootstrap never creates a second renderer slot.

The production design can later upgrade the persistence backend and two-slot pooling without changing the private product/build split.
