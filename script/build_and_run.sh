#!/usr/bin/env bash
set -euo pipefail

MODE="run"
OPEN_FILES=()

if [[ $# -gt 0 ]]; then
  case "$1" in
    run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
      MODE="$1"
      shift
      ;;
  esac
fi

if [[ $# -gt 0 ]]; then
  OPEN_FILES=("$@")
fi
APP_NAME="TahoePlayer"
BUNDLE_ID="dev.ehz.TahoePlayer"
MIN_SYSTEM_VERSION="26.0"
APP_VERSION="0.1.0"
APP_BUILD="1"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -f "$HOME/Library/Caches/TahoePlayer/Prepared/.*prepared\\.mp4" >/dev/null 2>&1 || true
rm -rf "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
fi

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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSQuitAlwaysKeepsWindows</key>
  <false/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Movie Files</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.movie</string>
        <string>public.mpeg-4</string>
        <string>com.apple.quicktime-movie</string>
        <string>public.avi</string>
        <string>org.webmproject.webm</string>
        <string>org.matroska.mkv</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

is_bundled_dependency() {
  local path="$1"
  [[ "$path" == "$BREW_PREFIX/"* ]]
}

is_already_bundled() {
  local path="$1"
  local bundled
  for bundled in "${BUNDLED_DYLIBS[@]}"; do
    [[ "$bundled" == "__sentinel__" ]] && continue
    if [[ "$bundled" == "$path" ]]; then
      return 0
    fi
  done
  return 1
}

read_linked_dylibs() {
  local binary="$1"
  otool -L "$binary" | awk 'NR > 1 {print $1}'
}

run_install_name_tool() {
  install_name_tool "$@" 2> >(grep -v "warning: changes being made to the file will invalidate the code signature" >&2)
}

run_codesign() {
  codesign "$@" 2> >(grep -v "replacing existing signature" >&2)
}

bundle_dylib_tree() {
  local path="$1"
  if ! is_bundled_dependency "$path"; then
    return
  fi
  if [[ ! -f "$path" ]]; then
    echo "warning: linked dependency not found: $path" >&2
    return
  fi
  if is_already_bundled "$path"; then
    return
  fi

  local basename destination dependency
  basename="$(basename "$path")"
  destination="$APP_FRAMEWORKS/$basename"
  cp -f "$path" "$destination"
  chmod u+w "$destination"
  BUNDLED_DYLIBS+=("$path")

  while IFS= read -r dependency; do
    bundle_dylib_tree "$dependency"
  done < <(read_linked_dylibs "$destination")
}

rewrite_dylib_load_commands() {
  local target="$1"
  local dependency replacement
  for dependency in "${BUNDLED_DYLIBS[@]}"; do
    [[ "$dependency" == "__sentinel__" ]] && continue
    replacement="$2/$(basename "$dependency")"
    if otool -L "$target" | grep -Fq "$dependency"; then
      run_install_name_tool -change "$dependency" "$replacement" "$target"
    fi
  done
}

bundle_and_sign_homebrew_dylibs() {
  BREW_PREFIX="$(brew --prefix)"
  BUNDLED_DYLIBS=("__sentinel__")

  local dependency bundled_path
  while IFS= read -r dependency; do
    bundle_dylib_tree "$dependency"
  done < <(read_linked_dylibs "$APP_BINARY")

  if [[ ${#BUNDLED_DYLIBS[@]} -le 1 ]]; then
    run_codesign --force --sign - "$APP_BUNDLE"
    return
  fi

  run_install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
  rewrite_dylib_load_commands "$APP_BINARY" "@executable_path/../Frameworks"

  for dependency in "${BUNDLED_DYLIBS[@]}"; do
    [[ "$dependency" == "__sentinel__" ]] && continue
    bundled_path="$APP_FRAMEWORKS/$(basename "$dependency")"
    run_install_name_tool -id "@rpath/$(basename "$dependency")" "$bundled_path"
    rewrite_dylib_load_commands "$bundled_path" "@loader_path"
    run_codesign --force --sign - "$bundled_path"
  done

  run_codesign --force --sign - "$APP_BUNDLE"
}

bundle_and_sign_homebrew_dylibs

open_app() {
  if [[ ${#OPEN_FILES[@]} -gt 0 ]]; then
    /usr/bin/open -n -F -a "$APP_BUNDLE" "${OPEN_FILES[@]}"
  else
    /usr/bin/open -n -F "$APP_BUNDLE"
  fi
}

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
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
