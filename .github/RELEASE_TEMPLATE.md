# FreeFlow <version>

> **Source-only alpha.** This release contains source archives only. It does not
> provide a prebuilt FreeFlow app, DMG, Developer ID signature, Apple
> notarization, or automatic updater.

FreeFlow is a free, open-source, English-first macOS dictation app. Hold Right
Option, speak, and release to transcribe locally and insert into the application
that was focused when recording began.

## Install

Follow the tagged `INSTALL.md` at
`https://github.com/dsvyro1414-lab/FreeFlow/blob/<tag>/INSTALL.md`
to review, build, and install the source. The guide includes a manual path and
an exact safe prompt for a coding agent. Do not download executables presented
by third parties as official FreeFlow builds.

## Verified for this alpha

- macOS deployment target: 14.0 or newer;
- host-native ad-hoc release build from source;
- Apple Silicon physical Right Option → Parakeet → ChatGPT/Codex insertion
  smoke;
- Accessibility and Microphone regrant against the exact installed ad-hoc
  identity;
- deterministic clipboard preservation/fallback policy tests;
- deterministic core tests when run with a matching full Xcode toolchain;
- staged license and third-party notice resources.

## Experimental or unverified

- Intel runtime behavior; `x86_64` is a compile target only;
- broad native, Chrome, Telegram, VS Code, and multi-display compatibility;
- complete Parakeet/Whisper quality and performance matrix;
- OpenAI, xAI, or Groq mode with a real user key;
- signed/notarized binary distribution and automatic updates.

## Permissions and privacy

- Microphone is required for recording.
- Accessibility enables the default Right Option listener and automatic
  insertion. A custom chord plus clipboard-only output is the reduced-permission
  path.
- Normal fallback copies the transcript and reports **Copied**. Temporary paste
  restores the previous clipboard only when target and pasteboard are unchanged;
  newer external clipboard writes are never overwritten, and **Copy last
  transcript** remains available.
- Parakeet and Whisper process audio locally after model download.
- Cloud modes are optional, send audio only to the selected provider, use the
  user's provider-specific API key, and may incur provider charges.

## Source integrity

- Tag: `<tag>`
- Commit: `<full commit SHA>`
- License: MIT; dependency/model terms are in `THIRD_PARTY_NOTICES.md`

## Known issues

- Rebuilding or updating an ad-hoc source installation can change its macOS
  privacy identity. If a permission appears enabled but FreeFlow cannot use it,
  follow the exact remove-and-readd recovery in `INSTALL.md`.
- Never paste private dictation, recordings, API keys, or unredacted logs here.

FreeFlow is an independent project. It is not affiliated with, endorsed by, or
sponsored by Wispr AI or Wispr Flow.
