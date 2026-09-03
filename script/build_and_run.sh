#!/bin/bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="FreeFlow"
BUNDLE_ID="com.dsvyro.freeflow"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALLED_APP="${HOME:?HOME is not set}/Applications/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_RESOURCES="$ROOT_DIR/Resources"
ICON_SOURCE="$SOURCE_RESOURCES/$APP_NAME.icns"
RELEASE_ENTITLEMENTS="$SOURCE_RESOURCES/$APP_NAME.entitlements"
MODULE_CACHE="$ROOT_DIR/.build/FreeFlowModuleCache"
SWIFTPM_CACHE="$ROOT_DIR/.build/SwiftPMCache"
SWIFTPM_CONFIG="$ROOT_DIR/.build/SwiftPMConfig"
SWIFTPM_SECURITY="$ROOT_DIR/.build/SwiftPMSecurity"
SWIFT_EXECUTABLE=""

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"

SWIFT_BUILD_ARGS=(
  --cache-path "$SWIFTPM_CACHE"
  --config-path "$SWIFTPM_CONFIG"
  --security-path "$SWIFTPM_SECURITY"
  --scratch-path "$ROOT_DIR/.build"
  --manifest-cache local
  --disable-keychain
)

usage() {
  echo "usage: $0 [run|--relaunch|--relaunch-staged|--relaunch-installed|--debug|--logs|--telemetry|--verify|--build-release|--install]" >&2
}

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

open_installed_app() {
  /usr/bin/open -n "$INSTALLED_APP"
}

preflight_build_tools() {
  local developer_path
  local sdk_path

  if ! developer_path="$(/usr/bin/xcode-select -p 2>/dev/null)" || [[ ! -d "$developer_path" ]]; then
    echo "Apple Command Line Tools are required to build $APP_NAME." >&2
    echo "Install them with: xcode-select --install" >&2
    exit 1
  fi

  if ! SWIFT_EXECUTABLE="$(/usr/bin/xcrun --find swift 2>/dev/null)" || [[ ! -x "$SWIFT_EXECUTABLE" ]]; then
    echo "The selected developer tools do not provide Swift." >&2
    echo "Install or repair them with: xcode-select --install" >&2
    exit 1
  fi

  if ! sdk_path="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null)" || [[ ! -d "$sdk_path" ]]; then
    echo "The selected developer tools do not provide a usable macOS SDK." >&2
    echo "Install or repair them with: xcode-select --install" >&2
    exit 1
  fi

  if [[ "$developer_path" == *"CommandLineTools"* ]]; then
    local fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
    if [[ ! -d "$fallback_sdk" ]]; then
      fallback_sdk="$sdk_path"
    fi
    export SDKROOT="$fallback_sdk"
    SWIFT_BUILD_ARGS+=(--disable-sandbox --sdk "$fallback_sdk")
    echo "Using the current Command Line Tools macOS SDK fallback."
  fi
}

reset_app_bundle() {
  if [[ "$APP_BUNDLE" != "$ROOT_DIR/dist/$APP_NAME.app" ]]; then
    echo "Refusing to replace an unexpected app bundle path: $APP_BUNDLE" >&2
    exit 1
  fi

  /bin/rm -rf -- "$APP_BUNDLE"
  /bin/mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
}

build_for_architecture() {
  local architecture="$1"
  local configuration="$2"
  local triple="${architecture}-apple-macosx${MIN_SYSTEM_VERSION}"
  local configuration_args=()

  if [[ "$configuration" == "release" ]]; then
    configuration_args+=(--configuration release)
  fi

  echo "Building $APP_NAME ($configuration) for $architecture..." >&2
  if ! "$SWIFT_EXECUTABLE" build "${SWIFT_BUILD_ARGS[@]}" "${configuration_args[@]}" \
    --triple "$triple" --product "$APP_NAME" >&2; then
    echo "$APP_NAME failed to build for $architecture." >&2
    return 1
  fi

  if ! "$SWIFT_EXECUTABLE" build "${SWIFT_BUILD_ARGS[@]}" "${configuration_args[@]}" \
    --triple "$triple" --show-bin-path | /usr/bin/tail -n 1; then
    echo "Could not locate the $configuration build output for $architecture." >&2
    return 1
  fi
}

stage_whisper_framework() {
  local expected_architecture="$1"
  local signing_style="$2"
  local staged_binary="$APP_FRAMEWORKS/whisper.framework/Versions/A/whisper"
  local whisper_framework

  whisper_framework="$(
    /usr/bin/find "$ROOT_DIR/.build" \
      -path '*whisper.xcframework/macos-arm64_x86_64/whisper.framework' \
      -print -quit
  )"

  if [[ -z "$whisper_framework" || ! -d "$whisper_framework" ]]; then
    echo "The built whisper.framework could not be located." >&2
    exit 1
  fi

  /usr/bin/ditto "$whisper_framework" "$APP_FRAMEWORKS/whisper.framework"
  if [[ "$signing_style" == "release" ]]; then
    local thin_binary="$staged_binary.thin"
    /usr/bin/lipo "$staged_binary" -thin "$expected_architecture" \
      -output "$thin_binary"
    /bin/chmod 0755 "$thin_binary"
    /bin/mv "$thin_binary" "$staged_binary"
  fi
  /usr/bin/lipo "$staged_binary" -verify_arch "$expected_architecture"
  /usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP_BINARY" 2>/dev/null || true

  if [[ "$signing_style" == "release" ]]; then
    /usr/bin/codesign --force --sign - --timestamp=none --options runtime \
      "$APP_FRAMEWORKS/whisper.framework"
  else
    /usr/bin/codesign --force --sign - --timestamp=none \
      "$APP_FRAMEWORKS/whisper.framework"
  fi
}

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>FreeFlow records audio only while you hold the dictation shortcut.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

stage_bundle_resources() {
  /usr/bin/install -m 0644 "$ROOT_DIR/LICENSE" "$APP_RESOURCES/LICENSE"
  /usr/bin/install -m 0644 "$ROOT_DIR/THIRD_PARTY_NOTICES.md" \
    "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"

  if [[ -f "$ICON_SOURCE" ]]; then
    /usr/bin/install -m 0644 "$ICON_SOURCE" "$APP_RESOURCES/$APP_NAME.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $APP_NAME.icns" \
      "$INFO_PLIST"
  fi
}

bundle_identifier() {
  local bundle="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$bundle/Contents/Info.plist" 2>/dev/null
}

validate_bundle_identifier() {
  local bundle="$1"
  local actual_identifier

  if [[ -L "$bundle" || ! -d "$bundle" ]]; then
    echo "Expected a regular app bundle at $bundle." >&2
    return 1
  fi

  if ! actual_identifier="$(bundle_identifier "$bundle")"; then
    echo "Could not read the bundle identifier from $bundle." >&2
    return 1
  fi

  if [[ "$actual_identifier" != "$BUNDLE_ID" ]]; then
    echo "Refusing bundle with identifier '$actual_identifier'; expected '$BUNDLE_ID'." >&2
    return 1
  fi
}

validate_staged_bundle() {
  local bundle="$1"

  validate_bundle_identifier "$bundle"
  /usr/bin/plutil -lint "$bundle/Contents/Info.plist" >/dev/null

  if [[ ! -x "$bundle/Contents/MacOS/$APP_NAME" ]]; then
    echo "The staged bundle is missing its executable." >&2
    return 1
  fi

  /usr/bin/codesign --verify --deep --strict "$bundle"
}

remove_staged_bundle_after_install() {
  if [[ "$APP_BUNDLE" != "$DIST_DIR/$APP_NAME.app" ]]; then
    echo "Refusing to remove an unexpected staged app path: $APP_BUNDLE" >&2
    return 1
  fi
  if [[ -L "$DIST_DIR" || ! -d "$DIST_DIR" ]]; then
    echo "Refusing to remove the staged app through an unsafe dist directory: $DIST_DIR" >&2
    return 1
  fi
  if [[ -L "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
    echo "Expected a regular staged app bundle at $APP_BUNDLE." >&2
    return 1
  fi

  validate_bundle_identifier "$APP_BUNDLE"
  /bin/rm -rf -- "$APP_BUNDLE"

  if [[ -e "$APP_BUNDLE" || -L "$APP_BUNDLE" ]]; then
    echo "Could not remove the staged app at $APP_BUNDLE." >&2
    return 1
  fi
}

validate_release_signature() {
  local bundle="$1"
  local entitlements_json
  local signing_details

  if ! signing_details="$(/usr/bin/codesign -dvv "$bundle" 2>&1)"; then
    echo "Could not inspect the release bundle signature." >&2
    return 1
  fi
  if [[ "$signing_details" != *"runtime"* ]]; then
    echo "The release bundle is not signed with hardened runtime." >&2
    return 1
  fi

  if ! entitlements_json="$(
    /usr/bin/codesign -d --entitlements :- "$bundle" 2>/dev/null \
      | /usr/bin/plutil -convert json -o - - 2>/dev/null
  )"; then
    echo "The release bundle is missing the audio-input entitlement." >&2
    return 1
  fi
  if [[ "$entitlements_json" != *'"com.apple.security.device.audio-input":true'* ]]; then
    echo "The release bundle is missing the audio-input entitlement." >&2
    return 1
  fi
  if [[ "$entitlements_json" != *'"com.apple.security.cs.disable-library-validation":true'* ]]; then
    echo "The release bundle cannot load the bundled ad-hoc whisper framework." >&2
    return 1
  fi
}

bundle_designated_requirement() {
  local bundle="$1"

  /usr/bin/codesign -d -r- "$bundle" 2>&1 \
    | /usr/bin/sed -n 's/^# designated => //p'
}

finish_bundle() {
  local signing_style="$1"

  write_info_plist
  stage_bundle_resources

  if [[ "$signing_style" == "release" ]]; then
    if [[ ! -f "$RELEASE_ENTITLEMENTS" ]]; then
      echo "Missing release entitlements: $RELEASE_ENTITLEMENTS" >&2
      exit 1
    fi
    /usr/bin/plutil -lint "$RELEASE_ENTITLEMENTS" >/dev/null
    /usr/bin/codesign --force --sign - --timestamp=none --options runtime \
      --entitlements "$RELEASE_ENTITLEMENTS" "$APP_BUNDLE"
  else
    /usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
  fi

  validate_staged_bundle "$APP_BUNDLE"
  if [[ "$signing_style" == "release" ]]; then
    validate_release_signature "$APP_BUNDLE"
  fi
}

build_universal_debug_bundle() {
  local arm64_build_dir
  local x86_64_build_dir

  if ! arm64_build_dir="$(build_for_architecture arm64 debug)"; then
    exit 1
  fi
  if ! x86_64_build_dir="$(build_for_architecture x86_64 debug)"; then
    exit 1
  fi

  reset_app_bundle
  /usr/bin/lipo -create "$arm64_build_dir/$APP_NAME" "$x86_64_build_dir/$APP_NAME" \
    -output "$APP_BINARY"
  /usr/bin/lipo "$APP_BINARY" -verify_arch arm64 x86_64
  /bin/chmod +x "$APP_BINARY"
  stage_whisper_framework "arm64" debug
  /usr/bin/lipo "$APP_FRAMEWORKS/whisper.framework/whisper" \
    -verify_arch arm64 x86_64
  finish_bundle debug
}

build_host_release_bundle() {
  local host_architecture
  local release_build_dir

  host_architecture="$(/usr/bin/uname -m)"
  case "$host_architecture" in
    arm64|x86_64) ;;
    *)
      echo "Unsupported host architecture: $host_architecture" >&2
      exit 1
      ;;
  esac

  if ! release_build_dir="$(build_for_architecture "$host_architecture" release)"; then
    exit 1
  fi

  reset_app_bundle
  /usr/bin/install -m 0755 "$release_build_dir/$APP_NAME" "$APP_BINARY"
  /usr/bin/lipo "$APP_BINARY" -verify_arch "$host_architecture"
  stage_whisper_framework "$host_architecture" release
  finish_bundle release

  echo "Built host-native release bundle: $APP_BUNDLE"
}

INSTALL_STAGE_DIR=""
INSTALL_BACKUP_DIR=""
INSTALL_BACKUP_APP=""
INSTALL_TARGET=""
INSTALL_ACTIVATION_STARTED=false
INSTALL_COMMITTED=false

safe_remove_install_temp() {
  local path="$1"
  local applications_dir="$2"

  case "$path" in
    "$applications_dir"/.FreeFlow-install.*|"$applications_dir"/.FreeFlow-rollback.*)
      /bin/rm -rf -- "$path"
      ;;
    "") ;;
    *)
      echo "Refusing to remove unexpected temporary path: $path" >&2
      return 1
      ;;
  esac
}

cleanup_interrupted_install() {
  local status="$?"
  local applications_dir="${HOME:?HOME is not set}/Applications"
  local preserve_backup=false

  trap - EXIT INT TERM
  set +e

  if [[ "$INSTALL_COMMITTED" != true ]]; then
    if [[ "$INSTALL_ACTIVATION_STARTED" == true \
      && ( -e "$INSTALL_TARGET" || -L "$INSTALL_TARGET" ) ]]; then
      if [[ -d "$INSTALL_STAGE_DIR" ]]; then
        /bin/mv "$INSTALL_TARGET" "$INSTALL_STAGE_DIR/Interrupted-$APP_NAME.app" || \
          preserve_backup=true
      else
        preserve_backup=true
      fi
    fi

    if [[ -d "$INSTALL_BACKUP_APP" ]]; then
      if [[ -e "$INSTALL_TARGET" || -L "$INSTALL_TARGET" ]]; then
        preserve_backup=true
        echo "Rollback copy preserved at $INSTALL_BACKUP_APP because the install target is occupied." >&2
      elif ! /bin/mv "$INSTALL_BACKUP_APP" "$INSTALL_TARGET"; then
        preserve_backup=true
        echo "Automatic rollback failed; previous app preserved at $INSTALL_BACKUP_APP." >&2
      fi
    fi
  fi

  safe_remove_install_temp "$INSTALL_STAGE_DIR" "$applications_dir"
  if [[ "$preserve_backup" != true ]]; then
    safe_remove_install_temp "$INSTALL_BACKUP_DIR" "$applications_dir"
  fi
  exit "$status"
}

install_release_bundle() {
  local applications_dir="${HOME:?HOME is not set}/Applications"
  local new_privacy_requirement
  local previous_privacy_requirement=""
  local privacy_identity_changed=false
  local staged_app

  if [[ -L "$applications_dir" ]]; then
    echo "Refusing to install through a symlinked Applications directory: $applications_dir" >&2
    exit 1
  fi
  if [[ -e "$applications_dir" && ! -d "$applications_dir" ]]; then
    echo "The install destination is not a directory: $applications_dir" >&2
    exit 1
  fi
  if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Quit FreeFlow, then run --install again." >&2
    exit 1
  fi

  /bin/mkdir -p "$applications_dir"
  INSTALL_TARGET="$applications_dir/$APP_NAME.app"
  INSTALL_STAGE_DIR="$(/usr/bin/mktemp -d "$applications_dir/.FreeFlow-install.XXXXXX")"
  staged_app="$INSTALL_STAGE_DIR/$APP_NAME.app"
  trap cleanup_interrupted_install EXIT INT TERM

  /usr/bin/ditto "$APP_BUNDLE" "$staged_app"
  validate_staged_bundle "$staged_app"
  validate_release_signature "$staged_app"
  if ! new_privacy_requirement="$(bundle_designated_requirement "$staged_app")" \
    || [[ -z "$new_privacy_requirement" ]]; then
    echo "Could not read the staged app's macOS privacy identity." >&2
    exit 1
  fi

  if [[ -e "$INSTALL_TARGET" || -L "$INSTALL_TARGET" ]]; then
    validate_bundle_identifier "$INSTALL_TARGET"
    previous_privacy_requirement="$(
      bundle_designated_requirement "$INSTALL_TARGET" 2>/dev/null || true
    )"
    if [[ -z "$previous_privacy_requirement" \
      || "$previous_privacy_requirement" != "$new_privacy_requirement" ]]; then
      privacy_identity_changed=true
    fi
    INSTALL_BACKUP_DIR="$(/usr/bin/mktemp -d "$applications_dir/.FreeFlow-rollback.XXXXXX")"
    INSTALL_BACKUP_APP="$INSTALL_BACKUP_DIR/$APP_NAME.app"
    /bin/mv "$INSTALL_TARGET" "$INSTALL_BACKUP_APP"
  fi

  INSTALL_ACTIVATION_STARTED=true
  if ! /bin/mv "$staged_app" "$INSTALL_TARGET"; then
    echo "Installation failed before the new bundle was activated; restoring the previous app." >&2
    exit 1
  fi

  if ! validate_staged_bundle "$INSTALL_TARGET" \
    || ! validate_release_signature "$INSTALL_TARGET"; then
    echo "Installed bundle validation failed; restoring the previous app." >&2
    /bin/mv "$INSTALL_TARGET" "$INSTALL_STAGE_DIR/Failed-$APP_NAME.app" || true
    exit 1
  fi

  remove_staged_bundle_after_install
  INSTALL_COMMITTED=true
  trap - EXIT INT TERM
  safe_remove_install_temp "$INSTALL_STAGE_DIR" "$applications_dir"
  safe_remove_install_temp "$INSTALL_BACKUP_DIR" "$applications_dir"

  echo "Installed $APP_NAME at $INSTALL_TARGET"
  echo "Open it from your Applications folder when you are ready to grant permissions."
  echo "After granting permissions, relaunch this exact bundle with: $0 --relaunch-installed"
  if [[ "$privacy_identity_changed" == true ]]; then
    echo "This ad-hoc update changed FreeFlow's macOS privacy identity."
    echo "If Accessibility looks On but Setup still says it is unavailable, remove the existing FreeFlow row in System Settings > Privacy & Security > Accessibility, then add and enable exactly: $INSTALL_TARGET"
    echo "Toggling the old row may not replace its stored code requirement."
  fi
}

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|\
    --build-release|build-release|--install|install|--relaunch|relaunch|\
    --relaunch-staged|relaunch-staged|\
    --relaunch-installed|relaunch-installed) ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ "$MODE" == "--relaunch" || "$MODE" == "relaunch" ]]; then
  if [[ -d "$APP_BUNDLE" && -d "$INSTALLED_APP" ]]; then
    echo "Two FreeFlow bundles exist with separate macOS privacy identities:" >&2
    echo "  staged:   $APP_BUNDLE" >&2
    echo "  installed: $INSTALLED_APP" >&2
    echo "Use --relaunch-staged or --relaunch-installed explicitly." >&2
    exit 2
  fi
  if [[ -d "$APP_BUNDLE" ]]; then
    validate_staged_bundle "$APP_BUNDLE"
    stop_running_app
    open_app
    exit 0
  fi
  if [[ -d "$INSTALLED_APP" ]]; then
    validate_staged_bundle "$INSTALLED_APP"
    validate_release_signature "$INSTALLED_APP"
    stop_running_app
    open_installed_app
    exit 0
  fi
  echo "No staged or installed FreeFlow app was found." >&2
  exit 1
fi

if [[ "$MODE" == "--relaunch-staged" || "$MODE" == "relaunch-staged" ]]; then
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "No staged app found. Build it before using --relaunch-staged." >&2
    exit 1
  fi
  validate_staged_bundle "$APP_BUNDLE"
  stop_running_app
  open_app
  exit 0
fi

if [[ "$MODE" == "--relaunch-installed" || "$MODE" == "relaunch-installed" ]]; then
  if [[ ! -d "$INSTALLED_APP" ]]; then
    echo "No installed app found at $INSTALLED_APP. Run $0 --install first." >&2
    exit 1
  fi
  validate_staged_bundle "$INSTALLED_APP"
  validate_release_signature "$INSTALLED_APP"
  stop_running_app
  open_installed_app
  exit 0
fi

preflight_build_tools
/bin/mkdir -p "$MODULE_CACHE"

if [[ "$MODE" == "--build-release" || "$MODE" == "build-release" ]]; then
  build_host_release_bundle
  exit 0
fi

if [[ "$MODE" == "--install" || "$MODE" == "install" ]]; then
  build_host_release_bundle
  install_release_bundle
  exit 0
fi

stop_running_app
build_universal_debug_bundle

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
    ;;
esac
