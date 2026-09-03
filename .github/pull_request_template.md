## Summary

Describe the user-visible change and why it belongs in the current alpha.

## Verification

- **Verified:**
- **Blocked:**
- **Inferred:**
- **Unimplemented:**

## Checklist

- [ ] The change is focused and does not overwrite unrelated work.
- [ ] Deterministic behavior has tests where practical.
- [ ] `swift format lint --strict --recursive Sources Tests Package.swift script/package_icns.swift` passes.
- [ ] `swift test` passes with full Xcode, or the exact toolchain blocker is documented.
- [ ] `./script/build_and_run.sh --build-release` and strict bundle verification pass when relevant.
- [ ] Physical Microphone/Accessibility/model/application checks are listed separately from build evidence.
- [ ] No recordings, models, secrets, private logs, generated bundles, or personal agent state are committed.
- [ ] Installation, privacy, permissions, and third-party notices are updated when affected.
- [ ] No claim implies Wispr affiliation, copied code, or unverified feature/hardware parity.
