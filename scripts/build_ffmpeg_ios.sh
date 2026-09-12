#!/usr/bin/env bash
set -euo pipefail

# Build an LGPL-only, dynamically linked FFmpeg for iOS.
#
# The output is a set of xcframeworks containing one framework per libav*
# library. Keep the frameworks as siblings of art3m1s_core in the app bundle;
# do not fold them into art3m1s_core with static archives.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

FFMPEG_VERSION="${FFMPEG_VERSION:-8.1.2}"
FFMPEG_BUILD_DIR="${FFMPEG_BUILD_DIR:-$PROJECT_DIR/.build/ffmpeg-ios}"
FFMPEG_OUT_DIR="${FFMPEG_OUT_DIR:-$PROJECT_DIR/ios/Frameworks}"
FFMPEG_SOURCE="${FFMPEG_SOURCE:-}"
FFMPEG_ARCHIVE="${FFMPEG_ARCHIVE:-}"
FFMPEG_SHA256="${FFMPEG_SHA256:-}"
FFMPEG_JOBS="${FFMPEG_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || printf '4')}"
IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}"

BUILD_DEVICE=1
BUILD_SIM=1
CLEAN=0
LIBRARIES=(avcodec avformat avutil swscale swresample)

usage() {
  cat <<'EOF'
Usage: scripts/build_ffmpeg_ios.sh [options]

Options:
  --device-only          Build only the iphoneos arm64 slice.
  --simulator-only       Build only the iphonesimulator arm64 slice.
  --clean                Remove previous FFmpeg build directories first.
  --source DIR           Use an existing FFmpeg source checkout.
  --archive FILE         Use an existing FFmpeg source archive.
  -h, --help             Show this help.

Environment:
  FFMPEG_VERSION         FFmpeg version. Default: 8.1.2.
  FFMPEG_SOURCE          Existing source checkout.
  FFMPEG_ARCHIVE         Existing source archive.
  FFMPEG_SHA256          Optional SHA-256 for the downloaded archive.
  FFMPEG_BUILD_DIR       Build directory. Default: .build/ffmpeg-ios.
  FFMPEG_OUT_DIR         xcframework output. Default: ios/Frameworks.
  FFMPEG_JOBS            Parallel build jobs.
  IPHONEOS_DEPLOYMENT_TARGET
                         Minimum iOS version. Default: 13.0.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-only)
      BUILD_DEVICE=1
      BUILD_SIM=0
      ;;
    --simulator-only)
      BUILD_DEVICE=0
      BUILD_SIM=1
      ;;
    --clean)
      CLEAN=1
      ;;
    --source)
      shift
      FFMPEG_SOURCE="${1:-}"
      ;;
    --archive)
      shift
      FFMPEG_ARCHIVE="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: $1 not found" >&2
    exit 1
  }
}

require curl
require install_name_tool
require lipo
require make
require otool
require tar
require vtool
require xcodebuild
require xcrun

if [[ "$CLEAN" == "1" ]]; then
  rm -rf "$FFMPEG_BUILD_DIR"
fi

mkdir -p "$FFMPEG_BUILD_DIR" "$FFMPEG_OUT_DIR"

source_dir="$FFMPEG_SOURCE"
if [[ -z "$source_dir" ]]; then
  archive="$FFMPEG_ARCHIVE"
  if [[ -z "$archive" ]]; then
    archive="$FFMPEG_BUILD_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz"
    if [[ ! -f "$archive" ]]; then
      echo "Downloading FFmpeg $FFMPEG_VERSION..."
      curl -fL --retry 3 \
        "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" \
        -o "$archive"
    fi
  fi
  if [[ -n "$FFMPEG_SHA256" ]]; then
    actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
    if [[ "$actual_sha256" != "$FFMPEG_SHA256" ]]; then
      echo "ERROR: FFmpeg archive checksum mismatch" >&2
      echo "  expected: $FFMPEG_SHA256" >&2
      echo "  actual:   $actual_sha256" >&2
      exit 1
    fi
  fi
  source_dir="$FFMPEG_BUILD_DIR/src/ffmpeg-$FFMPEG_VERSION"
  if [[ ! -x "$source_dir/configure" ]]; then
    rm -rf "$source_dir"
    mkdir -p "$(dirname "$source_dir")"
    tar -xf "$archive" -C "$(dirname "$source_dir")"
  fi
fi

if [[ ! -x "$source_dir/configure" ]]; then
  echo "ERROR: FFmpeg configure not found in $source_dir" >&2
  exit 1
fi

if [[ -f "$source_dir/RELEASE" ]]; then
  source_version="$(tr -d '[:space:]' < "$source_dir/RELEASE")"
  if [[ -n "$source_version" && "$source_version" != "$FFMPEG_VERSION" ]]; then
    echo "ERROR: source version $source_version does not match $FFMPEG_VERSION" >&2
    exit 1
  fi
fi

platform_tools() {
  local sdk="$1"
  CC="$(xcrun --sdk "$sdk" -f clang)"
  CXX="$(xcrun --sdk "$sdk" -f clang++)"
  AR="$(xcrun -f ar)"
  NM="$(xcrun -f nm)"
  RANLIB="$(xcrun -f ranlib)"
  STRIP="$(xcrun -f strip)"
  SDKROOT="$(xcrun --sdk "$sdk" --show-sdk-path)"
}

configure_build() {
  local build="$1"
  local sdk="$2"
  local minimum_flag="$3"

  platform_tools "$sdk"
  rm -rf "$build"
  mkdir -p "$build"

  (
    cd "$build"
    "$source_dir/configure" \
      --prefix="$build/prefix" \
      --target-os=darwin \
      --arch=arm64 \
      --cc="$CC" \
      --cxx="$CXX" \
      --ar="$AR" \
      --nm="$NM" \
      --ranlib="$RANLIB" \
      --strip="$STRIP" \
      --sysroot="$SDKROOT" \
      --enable-cross-compile \
      --enable-shared \
      --disable-static \
      --enable-pic \
      --disable-autodetect \
      --disable-programs \
      --disable-doc \
      --disable-debug \
      --disable-avdevice \
      --disable-avfilter \
      --disable-encoders \
      --disable-muxers \
      --disable-gpl \
      --disable-nonfree \
      --disable-version3 \
      --disable-videotoolbox \
      --install-name-dir=@rpath \
      --extra-cflags="-arch arm64 $minimum_flag -fPIC" \
      --extra-ldflags="-arch arm64 $minimum_flag"
  )
}

build_slice() {
  local build="$1"
  echo "Building FFmpeg $FFMPEG_VERSION in $build..."
  make -C "$build" -j"$FFMPEG_JOBS"
  make -C "$build" install
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
  <key>CFBundleIdentifier</key><string>org.ffmpeg.$name</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$FFMPEG_VERSION</string>
  <key>CFBundleVersion</key><string>$FFMPEG_VERSION</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
  <key>MinimumOSVersion</key><string>$IPHONEOS_DEPLOYMENT_TARGET</string>
</dict>
</plist>
PLIST
}

rewrite_dependencies() {
  local binary="$1"
  local dependency base
  while IFS= read -r dependency; do
    case "$dependency" in
      */libavcodec.*.dylib|@rpath/libavcodec.*.dylib|\
      */libavformat.*.dylib|@rpath/libavformat.*.dylib|\
      */libavutil.*.dylib|@rpath/libavutil.*.dylib|\
      */libswscale.*.dylib|@rpath/libswscale.*.dylib|\
      */libswresample.*.dylib|@rpath/libswresample.*.dylib)
        base="$(basename "$dependency")"
        base="${base%%.*}"
        install_name_tool -change "$dependency" \
          "@rpath/$base.framework/$base" "$binary"
        ;;
    esac
  done < <(otool -L "$binary" | awk 'NR > 1 {print $1}')
}

make_framework_slice() {
  local prefix="$1"
  local slice="$2"
  local platform="$3"
  local name source binary framework

  rm -rf "$slice"
  mkdir -p "$slice"

  # Rewrite the installed dylibs before copying them into frameworks. The
  # linker visits these files through prefix/lib and records their install
  # names in art3m1s_core, so they must already point at the runtime framework.
  for name in "${LIBRARIES[@]}"; do
    source="$(
      find "$prefix/lib" -maxdepth 1 -type f \
        -name "lib${name}.*.dylib" -print -quit
    )"
    if [[ -z "$source" ]]; then
      echo "ERROR: missing lib${name} dynamic library under $prefix/lib" >&2
      exit 1
    fi
    install_name_tool -id "@rpath/lib${name}.framework/lib${name}" "$source"
  done

  for name in "${LIBRARIES[@]}"; do
    source="$(
      find "$prefix/lib" -maxdepth 1 -type f \
        -name "lib${name}.*.dylib" -print -quit
    )"
    rewrite_dependencies "$source"
  done

  for name in "${LIBRARIES[@]}"; do
    source="$(
      find "$prefix/lib" -maxdepth 1 -type f \
        -name "lib${name}.*.dylib" -print -quit
    )"
    if [[ -z "$source" ]]; then
      echo "ERROR: missing lib${name} dynamic library under $prefix/lib" >&2
      exit 1
    fi
    framework="$slice/lib${name}.framework"
    binary="$framework/lib${name}"
    mkdir -p "$framework"
    cp "$source" "$binary"
    chmod u+w "$binary"
    install_name_tool -id "@rpath/lib${name}.framework/lib${name}" "$binary"
    write_framework_plist "$framework" "lib${name}" "$platform"
  done

  for name in "${LIBRARIES[@]}"; do
    rewrite_dependencies "$slice/lib${name}.framework/lib${name}"
  done
}

verify_slice() {
  local slice="$1"
  local label="$2"
  local allow_newer="$3"
  local name binary minimum
  for name in "${LIBRARIES[@]}"; do
    binary="$slice/lib${name}.framework/lib${name}"
    minimum="$(
      vtool -show-build "$binary" 2>/dev/null \
        | awk '$1 == "minos" {print $2; exit}'
    )"
    if [[ "$minimum" == "$IPHONEOS_DEPLOYMENT_TARGET" ]]; then
      continue
    fi
    if [[ "$allow_newer" == "1" ]] && version_at_least \
      "$minimum" "$IPHONEOS_DEPLOYMENT_TARGET"; then
      echo "WARN: $label $binary has minos $minimum (deployment target is $IPHONEOS_DEPLOYMENT_TARGET)"
      continue
    fi
    echo "ERROR: $label $binary has minos ${minimum:-unknown}, expected $IPHONEOS_DEPLOYMENT_TARGET" >&2
    exit 1
  done
}

version_at_least() {
  local actual="$1"
  local required="$2"
  local actual_major actual_minor required_major required_minor
  IFS=. read -r actual_major actual_minor _ <<< "$actual"
  IFS=. read -r required_major required_minor _ <<< "$required"
  if (( actual_major > required_major )); then
    return 0
  fi
  if (( actual_major < required_major )); then
    return 1
  fi
  (( actual_minor >= required_minor ))
}

write_manifest() {
  local manifest="$FFMPEG_OUT_DIR/FFmpeg-LGPL.txt"
  cat > "$manifest" <<EOF
FFmpeg $FFMPEG_VERSION
License: LGPL-2.1-or-later
Linkage: dynamic
Minimum iOS: $IPHONEOS_DEPLOYMENT_TARGET
Source: https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz
Build flags: --enable-shared --disable-static --disable-gpl --disable-nonfree
             --disable-version3 --disable-autodetect --disable-encoders
             --disable-muxers --disable-avdevice --disable-avfilter
EOF
  if [[ -f "$source_dir/LICENSE.md" ]]; then
    cp "$source_dir/LICENSE.md" "$FFMPEG_OUT_DIR/FFmpeg-LICENSE.md"
  fi
  if [[ -f "$source_dir/COPYING.LGPLv2.1" ]]; then
    cp "$source_dir/COPYING.LGPLv2.1" "$FFMPEG_OUT_DIR/FFmpeg-COPYING.LGPLv2.1"
  fi
}

package_slice() {
  local slice="$1"
  local name
  for name in "${LIBRARIES[@]}"; do
    local output="$FFMPEG_OUT_DIR/lib${name}.xcframework"
    local args=(-framework "$slice/lib${name}.framework")
    if [[ "$BUILD_SIM" == "1" ]]; then
      args+=(-framework "$FFMPEG_BUILD_DIR/simulator/lib${name}.framework")
    fi
    rm -rf "$output"
    xcodebuild -create-xcframework "${args[@]}" -output "$output"
  done
}

device_slice="$FFMPEG_BUILD_DIR/frameworks/device"
if [[ "$BUILD_DEVICE" == "1" ]]; then
  device_build="$FFMPEG_BUILD_DIR/device"
  configure_build "$device_build" iphoneos \
    "-miphoneos-version-min=$IPHONEOS_DEPLOYMENT_TARGET"
  build_slice "$device_build"
  make_framework_slice "$device_build/prefix" "$device_slice" iPhoneOS
  verify_slice "$device_slice" device 0
fi

if [[ "$BUILD_SIM" == "1" ]]; then
  simulator_build="$FFMPEG_BUILD_DIR/simulator"
  configure_build "$simulator_build" iphonesimulator \
    "-mios-simulator-version-min=$IPHONEOS_DEPLOYMENT_TARGET"
  build_slice "$simulator_build"
  make_framework_slice \
    "$simulator_build/prefix" \
    "$FFMPEG_BUILD_DIR/frameworks/simulator" \
    iPhoneSimulator
  verify_slice "$FFMPEG_BUILD_DIR/frameworks/simulator" simulator 1
fi

if [[ ! -d "$device_slice" ]]; then
  echo "ERROR: device slice is missing; run without --simulator-only first" >&2
  exit 1
fi

package_slice "$device_slice"
write_manifest

echo "FFmpeg $FFMPEG_VERSION dynamic frameworks prepared in $FFMPEG_OUT_DIR"
