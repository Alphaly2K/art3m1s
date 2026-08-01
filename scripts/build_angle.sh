#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ANGLE_TOOL_DIR="$PROJECT_DIR/tool/angle"
VCPKG_ROOT="${VCPKG_ROOT:-$PROJECT_DIR/.build/vcpkg}"
VCPKG_INSTALL_ROOT="${ANGLE_VCPKG_INSTALL_ROOT:-$PROJECT_DIR/.build/angle-vcpkg-installed}"
OVERLAY_PORTS="$ANGLE_TOOL_DIR/vcpkg/ports"
OVERLAY_TRIPLETS="$ANGLE_TOOL_DIR/vcpkg/triplets"
IOS_FRAMEWORK_DIR="$PROJECT_DIR/ios/Frameworks"

TARGET="${1:-darwin}"
shift || true
BUILD_SIM=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-only) BUILD_SIM=0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$TARGET" in
  ios|macos|darwin) ;;
  *) echo "Usage: $0 [ios|macos|darwin] [--device-only]" >&2; exit 2 ;;
esac

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: $1 not found" >&2
    exit 1
  }
}

ensure_vcpkg() {
  require git
  if [[ ! -d "$VCPKG_ROOT/.git" ]]; then
    mkdir -p "$(dirname "$VCPKG_ROOT")"
    git clone --depth 1 https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT"
  fi
  if [[ ! -x "$VCPKG_ROOT/vcpkg" ]]; then
    "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
  fi
}

build_angle_triplet() {
  local triplet="$1"
  "$VCPKG_ROOT/vcpkg" install --classic "angle[metal]:$triplet" \
    --overlay-ports="$OVERLAY_PORTS" \
    --overlay-triplets="$OVERLAY_TRIPLETS" \
    --x-install-root="$VCPKG_INSTALL_ROOT"
}

release_lib() {
  local triplet="$1"
  local name="$2"
  local path="$VCPKG_INSTALL_ROOT/$triplet/lib/liblib${name}_angle.dylib"
  [[ -f "$path" ]] || {
    echo "ERROR: ANGLE output missing: $path" >&2
    exit 1
  }
  printf '%s\n' "$path"
}

rewrite_zlib_to_system() {
  local binary="$1"
  local dependency
  while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    install_name_tool -change "$dependency" '/usr/lib/libz.1.dylib' "$binary"
  done < <(otool -L "$binary" | awk '$1 ~ /^@rpath\/libz(\.|$)/ { print $1 }')
}

write_framework_plist() {
  local framework="$1"
  local name="$2"
  local platform="$3"
  cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>org.chromium.angle.$name</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>7258</string>
  <key>CFBundleVersion</key><string>7258</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
  <key>MinimumOSVersion</key><string>13.0</string>
</dict>
</plist>
PLIST
}

make_ios_framework_slice() {
  local triplet="$1"
  local platform="$2"
  local output_root="$3"
  local gles_src egl_src
  gles_src="$(release_lib "$triplet" GLESv2)"
  egl_src="$(release_lib "$triplet" EGL)"

  local gles_fw="$output_root/libGLESv2.framework"
  local egl_fw="$output_root/libEGL.framework"
  rm -rf "$gles_fw" "$egl_fw"
  mkdir -p "$gles_fw" "$egl_fw"
  cp "$gles_src" "$gles_fw/libGLESv2"
  cp "$egl_src" "$egl_fw/libEGL"

  install_name_tool -id '@rpath/libGLESv2.framework/libGLESv2' "$gles_fw/libGLESv2"
  rewrite_zlib_to_system "$gles_fw/libGLESv2"
  install_name_tool -id '@rpath/libEGL.framework/libEGL' "$egl_fw/libEGL"
  install_name_tool -change '@rpath/liblibGLESv2_angle.dylib' \
    '@rpath/libGLESv2.framework/libGLESv2' "$egl_fw/libEGL"

  write_framework_plist "$gles_fw" libGLESv2 "$platform"
  write_framework_plist "$egl_fw" libEGL "$platform"
}

package_ios() {
  require xcodebuild
  require install_name_tool
  require otool
  build_angle_triplet arm64-ios-dynamic
  if [[ "$BUILD_SIM" == "1" ]]; then
    build_angle_triplet arm64-ios-sim-dynamic
  fi

  local slices="$PROJECT_DIR/.build/angle-frameworks"
  local device="$slices/device"
  local simulator="$slices/simulator"
  rm -rf "$slices"
  make_ios_framework_slice arm64-ios-dynamic iPhoneOS "$device"
  if [[ "$BUILD_SIM" == "1" ]]; then
    make_ios_framework_slice arm64-ios-sim-dynamic iPhoneSimulator "$simulator"
  fi

  mkdir -p "$IOS_FRAMEWORK_DIR"
  local name args
  for name in libEGL libGLESv2; do
    rm -rf "$IOS_FRAMEWORK_DIR/$name.xcframework"
    args=(-framework "$device/$name.framework")
    if [[ "$BUILD_SIM" == "1" ]]; then
      args+=(-framework "$simulator/$name.framework")
    fi
    xcodebuild -create-xcframework "${args[@]}" \
      -output "$IOS_FRAMEWORK_DIR/$name.xcframework"
  done
}

package_macos() {
  require install_name_tool
  require otool
  build_angle_triplet arm64-osx-dynamic

  local gles="$PROJECT_DIR/libGLESv2.dylib"
  local egl="$PROJECT_DIR/libEGL.dylib"
  cp "$(release_lib arm64-osx-dynamic GLESv2)" "$gles"
  cp "$(release_lib arm64-osx-dynamic EGL)" "$egl"
  install_name_tool -id '@loader_path/libGLESv2.dylib' "$gles"
  rewrite_zlib_to_system "$gles"
  install_name_tool -id '@loader_path/libEGL.dylib' "$egl"
  install_name_tool -change '@rpath/liblibGLESv2_angle.dylib' \
    '@loader_path/libGLESv2.dylib' "$egl"
}

ensure_vcpkg
case "$TARGET" in
  ios) package_ios ;;
  macos) package_macos ;;
  darwin)
    package_ios
    package_macos
    ;;
esac

echo "Official ANGLE Chromium 7258 prepared for $TARGET"
