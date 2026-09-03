# FreeFlow development status

Last updated: 2026-09-04

This file is the development handoff. Start future work by reading this file,
`README.md`, `INSTALL.md`, and `CONTRIBUTING.md`, then inspect the current Git and
GitHub state.

## Repository and application identity

- FreeFlow starts with a new Git history containing one root commit.
- Its source was initialized from the reviewed Swift snapshot
  `f8d08eb9861895c1e9114f38bef0eb250b0b69ff`; no source or Git history is reused
  from the deleted Electron FreeFlow repository.
- The Swift package, executable, bundle, UI, resources, tests, support paths,
  temporary-file prefix, and Keychain service use `FreeFlow`.
- The bundle identifier is `com.dsvyro.freeflow`. This is a separate macOS
  privacy identity.
- The public source channel is `main`. FreeFlow is currently distributed as a
  locally built, ad-hoc-signed app. No prebuilt app, DMG, Developer ID signature,
  notarization, Homebrew package, or updater is published.

## Implemented

- Menu-bar macOS 14 app with Right Option hold-to-talk and a configurable chord.
- Parakeet and Whisper local transcription.
- Optional OpenAI, xAI, and Groq transcription with separate Keychain accounts.
- Captured-target insertion, clipboard fallback, guarded clipboard restoration,
  and **Copy last transcript** recovery.
- Guided Setup, model management, Settings, and a recording/status pill.
- Source installer, pinned dependencies, MIT license, third-party notices, and CI.

## Verified by GitHub Actions

The current `main` workflow verifies:

- Swift Format strict lint and the full XCTest suite passed.
- The FreeFlow executable compiled for both `arm64` and `x86_64`.
- The app bundle, signature, entitlements, bundle identifier, icon, licenses,
  and absence of bundled models or common secrets were verified.
- A fresh macOS 14 checkout built and installed
  `~/Applications/FreeFlow.app` without launching it.

CI compilation for `x86_64` is not a physical Intel runtime test.

## User-confirmed physical verification

The project owner confirmed the following on the current FreeFlow identity on
2026-09-04:

- The installed app launches and guided Setup completes.
- Microphone and Accessibility permission flows work.
- Right Option recording, local transcription, and target-field insertion work.
- Real-key transcription works through OpenAI, xAI, and Groq.

## Remaining work

- Test runtime behavior on Intel hardware if Intel support is retained.
- Publish latency, memory, and transcript-quality measurements.
- Add a supported prebuilt distribution only after Developer ID signing,
  notarization, and a clean-machine install/update test are complete.

Keep CI-verified, user-confirmed, inferred, and unimplemented results separate.
