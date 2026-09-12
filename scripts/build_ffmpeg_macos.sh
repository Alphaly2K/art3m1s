#!/usr/bin/env bash
set -euo pipefail

# Build an LGPL-only, dynamically linked FFmpeg for macOS arm64.
#
# The runtime links these libraries through @rpath. Keep them beside
# libart3m1s_core in the app bundle instead of folding them into the Rust
# dynamic library.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

FFMPEG_VERSION="${FFMPEG_VERSION:-8.1.2}"
FFMPEG_BUILD_DIR="${FFMPEG_BUILD_DIR:-$PROJECT_DIR/.build/ffmpeg-macos}"
FFMPEG_SOURCE="${FFMPEG_SOURCE:-}"
FFMPEG_ARCHIVE="${FFMPEG_ARCHIVE:-}"
FFMPEG_SHA256="${FFMPEG_SHA256:-}"
FFMPEG_JOBS="${FFMPEG_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || printf '4')}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

usage() {
  cat <<'EOF'
Usage: scripts/build_ffmpeg_macos.sh [options]

Options:
  --source DIR   Use an existing FFmpeg source checkout.
  --archive FILE Use an existing FFmpeg source archive.
  --clean        Remove the previous macOS FFmpeg build first.
  -h, --help     Show this help.

Environment:
  FFMPEG_VERSION             FFmpeg version. Default: 8.1.2.
  FFMPEG_BUILD_DIR           Build directory. Default: .build/ffmpeg-macos.
  FFMPEG_SOURCE              Existing source checkout.
  FFMPEG_ARCHIVE             Existing source archive.
  FFMPEG_SHA256              Optional SHA-256 for the archive.
  FFMPEG_JOBS                Parallel build jobs.
  MACOSX_DEPLOYMENT_TARGET   Minimum macOS version. Default: 11.0.
EOF
}

CLEAN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      shift
      FFMPEG_SOURCE="${1:-}"
      ;;
    --archive)
      shift
      FFMPEG_ARCHIVE="${1:-}"
      ;;
    --clean)
      CLEAN=1
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

require install_name_tool
require make
require otool
require xcrun

if [[ "$CLEAN" == "1" ]]; then
  rm -rf "$FFMPEG_BUILD_DIR"
fi
mkdir -p "$FFMPEG_BUILD_DIR"

source_dir="$FFMPEG_SOURCE"
if [[ -z "$source_dir" ]]; then
  ios_source="$PROJECT_DIR/.build/ffmpeg-ios/src/ffmpeg-$FFMPEG_VERSION"
  if [[ -x "$ios_source/configure" ]]; then
    source_dir="$ios_source"
  else
    archive="$FFMPEG_ARCHIVE"
    if [[ -z "$archive" ]]; then
      archive="$FFMPEG_BUILD_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz"
      if [[ ! -f "$archive" ]]; then
        require curl
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
fi

if [[ ! -x "$source_dir/configure" ]]; then
  echo "ERROR: FFmpeg configure not found in $source_dir" >&2
  exit 1
fi

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
CC="$(xcrun --sdk macosx -f clang)"
CXX="$(xcrun --sdk macosx -f clang++)"
AR="$(xcrun -f ar)"
NM="$(xcrun -f nm)"
RANLIB="$(xcrun -f ranlib)"
STRIP="$(xcrun -f strip)"
PREFIX="$FFMPEG_BUILD_DIR/prefix"
BUILD="$FFMPEG_BUILD_DIR/build"

rm -rf "$BUILD" "$PREFIX"
mkdir -p "$BUILD" "$PREFIX"

(
  cd "$BUILD"
  "$source_dir/configure" \
    --prefix="$PREFIX" \
    --target-os=darwin \
    --arch=arm64 \
    --cc="$CC" \
    --cxx="$CXX" \
    --ar="$AR" \
    --nm="$NM" \
    --ranlib="$RANLIB" \
    --strip="$STRIP" \
    --sysroot="$SDKROOT" \
    --host-cc="$CC" \
    --host-cflags="--sysroot=$SDKROOT" \
    --host-ldflags="--sysroot=$SDKROOT" \
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
    --install-name-dir=@rpath \
    --extra-cflags="-arch arm64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -fPIC" \
    --extra-ldflags="-arch arm64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
)

make -C "$BUILD" -j"$FFMPEG_JOBS"
make -C "$BUILD" install

cp "$source_dir/LICENSE.md" "$PREFIX/FFmpeg-LICENSE.md"
cp "$source_dir/COPYING.LGPLv2.1" "$PREFIX/FFmpeg-COPYING.LGPLv2.1"

for library in libavcodec.62.dylib \
  libavformat.62.dylib \
  libavutil.60.dylib \
  libswresample.6.dylib \
  libswscale.9.dylib; do
  if [[ ! -f "$PREFIX/lib/$library" ]]; then
    echo "ERROR: missing FFmpeg library: $PREFIX/lib/$library" >&2
    exit 1
  fi
done

echo "FFmpeg $FFMPEG_VERSION LGPL dynamic libraries prepared in $PREFIX/lib"
