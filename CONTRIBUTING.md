# Contributing to FreeFlow

Thanks for helping make private, high-quality dictation available without a
subscription.

## Development setup

1. Use macOS 14 or newer with a full, matching Xcode toolchain selected.
2. Read `AGENTS.md`, `INSTALL.md`, and `plan.md`.
3. Confirm `git status --short --branch` and inspect the files you will change.
4. Run the deterministic checks:

   ```bash
   swift format lint --strict --recursive Sources Tests Package.swift script/package_icns.swift
   swift test
   ./script/build_and_run.sh --build-release
   codesign --verify --deep --strict dist/FreeFlow.app
   plutil -lint dist/FreeFlow.app/Contents/Info.plist
   ```

The staged release build must contain `Contents/Resources/LICENSE`,
`Contents/Resources/THIRD_PARTY_NOTICES.md`, and the source-matching
`Contents/Resources/FreeFlow.icns`; `CFBundleIconFile` must name that icon.
`--build-release` does not launch the app. Use `--relaunch-staged` for
`dist/FreeFlow.app`, or `--relaunch-installed` for the copy in
`~/Applications`. Bare `--relaunch` refuses to guess when both exist. The
explicit relaunch modes avoid rebuilding so physical tests do not silently
change the selected bundle's ad-hoc signature and macOS privacy identity.

## Physical checks

Code changes touching shortcuts, audio, insertion, models, permissions, or the
pill need proportional real-app testing. At minimum, record what was and was not
checked:

- Right Option press/release and Left Option isolation;
- one custom chord round trip;
- normal clipboard fallback, guarded temporary-paste restoration, and
  **Copy last transcript** recovery;
- one native and one Chromium/Electron text field when relevant;
- denied permission, short recording, and repeated-use behavior;
- model download/removal only when the test explicitly requires network use.

Never use a real secret or sensitive recording in a test. Any cloud API smoke
test requires an explicit user-supplied key and approval because it can incur
cost and transmit audio.

## Pull requests

- Keep each pull request focused and explain the user-visible behavior.
- Add deterministic tests for new logic and regression fixes.
- List **verified**, **blocked**, **inferred**, and **unimplemented** results
  separately.
- Do not claim Intel support from cross-compilation alone.
- Update installation, permissions, privacy, and third-party notices when they
  change.
- Do not commit speech models, recordings, API keys, generated app bundles,
  private logs, or personal agent configuration.
- Preserve the English-first behavior, target-app safety, and clipboard fallback.

Use the issue templates for reproducible reports. Security-sensitive findings
must follow [`SECURITY.md`](SECURITY.md), not a public issue.

## Code style

- Keep SwiftUI as the source of truth for app state.
- Keep AppKit bridges narrow and explicit.
- Prefer platform frameworks over additional dependencies.
- Never silently rewrite a user's dictated meaning.
- Pin dependencies and review their license and distribution obligations.
