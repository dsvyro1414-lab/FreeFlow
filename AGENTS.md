# Instructions for coding agents

Read [`INSTALL.md`](INSTALL.md) before any build or install; it is the canonical
source for commands, network boundaries, permission stops, and the exact
user-facing install prompt. Also inspect `README.md`, `plan.md`, the requested
files, Git status, and the configured remote.

- This is a clean-room repository. Never copy code, assets, or history from a
  previous FreeFlow repository.
- Preserve unrelated user changes. Never commit generated apps, models,
  recordings, secrets, private logs, or personal agent state.
- Source-only alpha means no official binary, Developer ID, notarization, DMG,
  or updater claim. Do not work around macOS security.
- Do not launch FreeFlow, change tools or system settings, request permissions,
  record audio, download models, or use OpenAI without explicit approval.
- After permissions are granted, relaunch the same bundle without rebuilding:
  `--relaunch-staged` targets `dist/FreeFlow.app`, while
  `--relaunch-installed` targets `~/Applications/FreeFlow.app`. Bare
  `--relaunch` is allowed only when the target is unambiguous.
- Keep local processing distinct from optional paid cloud processing. Keep
  Microphone distinct from optional Accessibility/reduced-permission output.
- Normal fallback copies the transcript. Temporary paste restores the previous
  clipboard only if target and pasteboard are unchanged; never overwrite a
  newer external clipboard write. **Copy last transcript** remains recovery.
- FreeFlow is independent from Wispr AI/Wispr Flow; never imply affiliation,
  copied code, or complete parity.
- Validate proportionally using `INSTALL.md` and `CONTRIBUTING.md`. Report
  **verified**, **blocked**, **inferred**, and **unimplemented** separately;
  Intel cross-compilation is not a runtime test.
