# Security policy

FreeFlow handles microphone audio, Accessibility access, clipboard contents,
downloaded model files, and optional API keys. Please report vulnerabilities
privately and avoid including real dictated content or credentials.

## Supported versions

FreeFlow is currently a source-only alpha. Security fixes are made on `main`.
Older commits and personal forks are not maintained releases.

There is no official prebuilt binary, Developer ID signature, notarization, or
automatic update channel at this stage.

## Report a vulnerability

Use GitHub's private
[security advisory form](https://github.com/dsvyro1414-lab/FreeFlow/security/advisories/new).
Do not open a public issue with exploit details. If private reporting is
temporarily unavailable, do not publish the report; contact the repository
owner through their GitHub profile and ask for a private channel.

Include only the minimum safe information:

- affected commit or source release;
- macOS version and CPU architecture;
- local model or selected cloud provider, without any API key;
- concise reproduction steps using synthetic text/audio;
- expected and observed behavior;
- whether Microphone or Accessibility was granted;
- a redacted crash excerpt, if needed.

Never attach recordings, complete logs containing dictation, Keychain output,
API keys, tokens, private file paths, or other people's data.

## In-scope examples

- audio surviving outside the documented temporary-file lifecycle;
- secrets exposed outside Keychain or sent to an unintended destination;
- local mode uploading recorded audio;
- unsafe model download, integrity, or path handling;
- Accessibility behavior targeting the wrong application or text field;
- command execution, privilege escalation, or tampered release resources.

Ordinary transcription quality, unsupported Intel behavior, and application
compatibility bugs belong in the public bug template after private data is
removed.

## Response expectations

This is a volunteer alpha project with no response-time SLA. The maintainer will
acknowledge and triage reports on a best-effort basis, coordinate a fix and
disclosure window when appropriate, and credit reporters who request attribution.
