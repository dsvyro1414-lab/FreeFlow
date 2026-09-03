# Install FreeFlow from source

FreeFlow is currently a source-only alpha published from `main`. It builds
locally and installs an ad-hoc-signed app at
`~/Applications/FreeFlow.app`.

## Install with a coding agent

Give the agent this repository and prompt:

```text
Install FreeFlow from:
https://github.com/dsvyro1414-lab/FreeFlow.git

Use a new checkout of main, record the exact commit, then inspect INSTALL.md,
Package.swift, Package.resolved, and script/build_and_run.sh before running it.
Stop if the origin, branch, commit, or working tree is dirty or unexpected.

Do not use sudo, disable Gatekeeper, remove quarantine, change developer tools,
or modify other apps. Install only to ~/Applications/FreeFlow.app.

Run ./script/build_and_run.sh --install. It must build from source without
launching FreeFlow. Verify the signature, bundle ID com.dsvyro.freeflow,
architecture, minimum macOS version, icon, LICENSE, and THIRD_PARTY_NOTICES.md.

After verification, launch ~/Applications/FreeFlow.app and guide me through
the visible Setup. Explain each permission and wait for me to click it, download
the model, record the test, or enter any API key myself.
```

## Manual installation

### 1. Prerequisites

- macOS 14 or newer
- Apple Command Line Tools or full Xcode with Swift 6
- Network access for pinned Swift dependencies and the model you choose

Check the tools:

```bash
sw_vers -productVersion
xcode-select -p
swift --version
```

If Command Line Tools are missing, macOS can install them with:

```bash
xcode-select --install
```

### 2. Clone the current source

```bash
git clone https://github.com/dsvyro1414-lab/FreeFlow.git
cd FreeFlow
git remote get-url origin
git branch --show-current
git rev-parse HEAD
git status --short --branch
```

### 3. Build and install

Quit FreeFlow if it is running, then run:

```bash
./script/build_and_run.sh --install
```

The script does not use `sudo`, launch the app, or change Gatekeeper. It replaces
only an existing app with bundle ID `com.dsvyro.freeflow` and rolls back a
failed update. After a successful install, it removes the temporary
`dist/FreeFlow.app` build so macOS sees only the installed copy.

### 4. Verify and launch

```bash
codesign --verify --deep --strict "$HOME/Applications/FreeFlow.app"
plutil -p "$HOME/Applications/FreeFlow.app/Contents/Info.plist"
file "$HOME/Applications/FreeFlow.app/Contents/MacOS/FreeFlow"
open "$HOME/Applications/FreeFlow.app"
```

Setup will ask you to choose a mode, download a local model, allow Microphone,
run a short test, and optionally enable Accessibility for Right Option and
automatic insertion.

If FreeFlow needs a restart after you grant a permission, relaunch the exact
installed bundle without rebuilding or signing it again:

```bash
./script/build_and_run.sh --relaunch-installed
```

Use `--relaunch-staged` only for the development bundle in `dist/`. Bare
`--relaunch` refuses to guess when both copies exist because they may have
different ad-hoc identities.

If Accessibility already shows FreeFlow as enabled but Setup still reports it
as unavailable, the visible row can belong to an older ad-hoc build. Remove that
FreeFlow row in **System Settings > Privacy & Security > Accessibility**, then
add and enable exactly `~/Applications/FreeFlow.app`. Toggling the old row may
not replace the code requirement stored by macOS. After granting access, use
`--relaunch-installed`; it opens the same bytes without rebuilding or signing
them again.

## Updates

Fetch and review the new `main` commit, update with a fast-forward only, quit
FreeFlow, then run `--install` again. Because each source build is ad-hoc signed,
macOS may ask for Microphone or Accessibility again. When an update changes the
app's privacy identity, the installer prints the exact remove-and-readd recovery
path instead of silently resetting a system permission.

## Current limits

- Apple Silicon is the tested path; Intel runtime remains experimental.
- Full unit tests require full Xcode with XCTest.
- There is no notarized binary, DMG, Homebrew package, or updater yet.
