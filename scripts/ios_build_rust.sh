#!/usr/bin/env bash
set -euo pipefail

# ── iOS Rust 动态 Framework 编译脚本 ────────────────────────────────────
# 从 Rust 源码编译 cdylib，分别封装真机/模拟器 framework，再组合为
# .xcframework，输出到
# ios/Frameworks/ 供 CocoaPods vendored_frameworks 使用。
#
# 用法:
#   ./scripts/ios_build_rust.sh [--release] [--device-only] [--sign "证书名"]
#
# 前置条件:
#   1. Rust 工具链: rustup target add aarch64-apple-ios aarch64-apple-ios-sim
#   2. 环境变量 CORE_SRC / PFS_SRC 指向 Rust 项目目录

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$PROJECT_DIR/ios/Frameworks"

# ── 可配置: Rust 项目路径 ──────────────────────────────────────────────
CORE_SRC="${CORE_SRC:-$PROJECT_DIR/../art3m1s-core}"
PFS_SRC="${PFS_SRC:-$CORE_SRC/crates/pfs-upk-rust}"
if [[ -z "${METALANGLE_DEVICE_FRAMEWORK:-}" ]]; then
  if [[ -d "$OUT_DIR/MetalANGLEDevice.framework" ]]; then
    METALANGLE_DEVICE_FRAMEWORK="$OUT_DIR/MetalANGLEDevice.framework"
  else
    METALANGLE_DEVICE_FRAMEWORK="$OUT_DIR/MetalANGLE.framework"
  fi
fi
METALANGLE_SIM_FRAMEWORK="${METALANGLE_SIM_FRAMEWORK:-$OUT_DIR/MetalANGLESimulator.framework}"

# ── 参数解析 ────────────────────────────────────────────────────────────
PROFILE="release"
CODE_SIGN_ID=""
BUILD_SIM=1
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)   PROFILE="debug" ;;
    --release) PROFILE="release" ;;
    --device-only) BUILD_SIM=0 ;;
    --sign)
      shift
      CODE_SIGN_ID="${1:-}"
      ;;
  esac
  shift
done

CARGO_FLAGS=()
TARGET_DIR_SUFFIX="debug"
if [[ "$PROFILE" == "release" ]]; then
  CARGO_FLAGS=(--release)
  TARGET_DIR_SUFFIX="release"
fi

# ── 工具检测 ────────────────────────────────────────────────────────────
require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 not found"; exit 1; }; }
require cargo
require lipo
require xcodebuild
require install_name_tool

# ── iOS targets ─────────────────────────────────────────────────────────
IOS_DEVICE_TARGET="aarch64-apple-ios"
IOS_SIM_ARM64_TARGET="aarch64-apple-ios-sim"

check_target() {
  rustup target list --installed | grep -q "$1" || {
    echo "Rust target $1 未安装，正在安装..."
    rustup target add "$1"
  }
}

check_target "$IOS_DEVICE_TARGET"
if [[ "$BUILD_SIM" == "1" ]]; then
  check_target "$IOS_SIM_ARM64_TARGET"
fi

# ── 生成 XCFramework ────────────────────────────────────────────────────
write_framework_plist() {
  local fw_dir="$1"
  local lib_name="$2"
  local bundle_id="$3"
  local platform_name="$4"
  local framework_version="$5"

  cat > "$fw_dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$lib_name</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$lib_name</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$framework_version</string>
    <key>CFBundleVersion</key>
    <string>$framework_version</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$platform_name</string>
    </array>
    <key>MinimumOSVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST
}

make_framework_slice() {
  local lib_name="$1"
  local dylib="$2"
  local fw_dir="$3"
  local bundle_id="$4"
  local platform_name="$5"
  local framework_version="$6"

  rm -rf "$fw_dir"
  mkdir -p "$fw_dir"
  cp "$dylib" "$fw_dir/$lib_name"
  install_name_tool -id "@rpath/${lib_name}.framework/$lib_name" \
    "$fw_dir/$lib_name"
  write_framework_plist \
    "$fw_dir" "$lib_name" "$bundle_id" "$platform_name" "$framework_version"

  if [[ -n "$CODE_SIGN_ID" ]]; then
    echo "  -> 签名 $platform_name slice: $CODE_SIGN_ID"
    codesign --force --sign "$CODE_SIGN_ID" --timestamp=none "$fw_dir"
  fi
}

make_framework() {
  local lib_name="$1"           # e.g. art3m1s_core
  local src_dir="$2"
  local bundle_id="$3"          # e.g. moe.alphaly.art3m1s.core

  if [[ ! -d "$src_dir" ]]; then
    echo "WARN: $src_dir 不存在，跳过 $lib_name"
    return
  fi

  echo ""
  echo "=== 编译 $lib_name ($PROFILE) ==="
  local crate_version
  crate_version="$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "$src_dir/Cargo.toml")"
  if [[ -z "$crate_version" ]]; then
    echo "ERROR: 无法从 $src_dir/Cargo.toml 读取 crate version"
    exit 1
  fi

  echo "  -> $IOS_DEVICE_TARGET"
  cargo build "${CARGO_FLAGS[@]}" --lib \
    --manifest-path "$src_dir/Cargo.toml" \
    --target "$IOS_DEVICE_TARGET"

  if [[ "$BUILD_SIM" == "1" ]]; then
    echo "  -> $IOS_SIM_ARM64_TARGET"
    cargo build "${CARGO_FLAGS[@]}" --lib \
      --manifest-path "$src_dir/Cargo.toml" \
      --target "$IOS_SIM_ARM64_TARGET"
  fi

  local device_dylib="$src_dir/target/$IOS_DEVICE_TARGET/$TARGET_DIR_SUFFIX/lib${lib_name}.dylib"
  local sim_arm64_dylib="$src_dir/target/$IOS_SIM_ARM64_TARGET/$TARGET_DIR_SUFFIX/lib${lib_name}.dylib"

  if [[ ! -f "$device_dylib" ]]; then
    echo "ERROR: $lib_name 编译产物缺失"
    exit 1
  fi

  local slices_dir="$OUT_DIR/.ios-framework-build/$lib_name"
  local device_fw="$slices_dir/device/${lib_name}.framework"
  local sim_fw="$slices_dir/simulator/${lib_name}.framework"
  local xcframework="$OUT_DIR/${lib_name}.xcframework"

  make_framework_slice \
    "$lib_name" "$device_dylib" "$device_fw" "$bundle_id" "iPhoneOS" "$crate_version"

  local xcframework_args=(-framework "$device_fw")
  if [[ "$BUILD_SIM" == "1" ]]; then
    make_framework_slice \
      "$lib_name" "$sim_arm64_dylib" "$sim_fw" "$bundle_id" "iPhoneSimulator" "$crate_version"
    xcframework_args+=(-framework "$sim_fw")
  fi

  rm -rf "$xcframework" "$OUT_DIR/${lib_name}.framework"
  echo "  -> 生成 ${lib_name}.xcframework"
  xcodebuild -create-xcframework \
    "${xcframework_args[@]}" \
    -output "$xcframework"

  echo "  -> $xcframework"
}

make_metalangle_xcframework() {
  if [[ ! -d "$METALANGLE_DEVICE_FRAMEWORK" ]]; then
    echo "ERROR: 缺少真机 MetalANGLE: $METALANGLE_DEVICE_FRAMEWORK"
    exit 1
  fi
  if [[ "$BUILD_SIM" == "1" ]] && [[ ! -d "$METALANGLE_SIM_FRAMEWORK" ]]; then
    echo "ERROR: simulator 构建需要 METALANGLE_SIM_FRAMEWORK"
    exit 1
  fi

  echo ""
  echo "=== 生成 MetalANGLE XCFramework ==="
  local slices_dir="$OUT_DIR/.ios-framework-build/MetalANGLE"
  local device_fw="$slices_dir/device/MetalANGLE.framework"
  local sim_fw="$slices_dir/simulator/MetalANGLE.framework"
  local xcframework="$OUT_DIR/MetalANGLE.xcframework"

  rm -rf "$slices_dir" "$xcframework"
  mkdir -p "$(dirname "$device_fw")"
  cp -R "$METALANGLE_DEVICE_FRAMEWORK" "$device_fw"
  rm -rf "$device_fw/_CodeSignature"
  lipo "$METALANGLE_DEVICE_FRAMEWORK/MetalANGLE" -thin arm64 \
    -output "$device_fw/MetalANGLE"
  install_name_tool -id "@rpath/MetalANGLE.framework/MetalANGLE" \
    "$device_fw/MetalANGLE"
  if [[ -n "$CODE_SIGN_ID" ]]; then
    codesign --force --sign "$CODE_SIGN_ID" --timestamp=none "$device_fw"
  fi

  local xcframework_args=(-framework "$device_fw")
  if [[ "$BUILD_SIM" == "1" ]]; then
    mkdir -p "$(dirname "$sim_fw")"
    cp -R "$METALANGLE_SIM_FRAMEWORK" "$sim_fw"
    rm -rf "$sim_fw/_CodeSignature"
    lipo "$METALANGLE_SIM_FRAMEWORK/MetalANGLE" -thin arm64 \
      -output "$sim_fw/MetalANGLE"
    install_name_tool -id "@rpath/MetalANGLE.framework/MetalANGLE" \
      "$sim_fw/MetalANGLE"
    if [[ -n "$CODE_SIGN_ID" ]]; then
      codesign --force --sign "$CODE_SIGN_ID" --timestamp=none "$sim_fw"
    fi
    xcframework_args+=(-framework "$sim_fw")
  fi

  xcodebuild -create-xcframework \
    "${xcframework_args[@]}" \
    -output "$xcframework"

  # 本地 Pod 根目录会进入 FRAMEWORK_SEARCH_PATHS。若保留同名的真机
  # MetalANGLE.framework，simulator 链接器会优先捡到它而绕过 XCFramework。
  if [[ "$METALANGLE_DEVICE_FRAMEWORK" == "$OUT_DIR/MetalANGLE.framework" ]]; then
    rm -rf "$OUT_DIR/MetalANGLEDevice.framework"
    mv "$METALANGLE_DEVICE_FRAMEWORK" "$OUT_DIR/MetalANGLEDevice.framework"
    METALANGLE_DEVICE_FRAMEWORK="$OUT_DIR/MetalANGLEDevice.framework"
  fi
  if [[ "$BUILD_SIM" == "1" ]] && \
     [[ "$METALANGLE_SIM_FRAMEWORK" != "$OUT_DIR/MetalANGLESimulator.framework" ]]; then
    rm -rf "$OUT_DIR/MetalANGLESimulator.framework"
    cp -R "$METALANGLE_SIM_FRAMEWORK" "$OUT_DIR/MetalANGLESimulator.framework"
    METALANGLE_SIM_FRAMEWORK="$OUT_DIR/MetalANGLESimulator.framework"
  fi
  echo "  -> $xcframework"
}

# ── 编译 ────────────────────────────────────────────────────────────────
mkdir -p "$OUT_DIR"

make_framework "art3m1s_core" "$CORE_SRC" "moe.alphaly.art3m1s.core"
make_framework "pfs_upk"       "$PFS_SRC"  "moe.alphaly.art3m1s.pfs"
make_metalangle_xcframework

echo ""
echo "=== 完成 ==="
echo "XCFrameworks 已输出到: $OUT_DIR"
find "$OUT_DIR" -maxdepth 2 -name '*.xcframework' -print
echo ""
echo "若未签名，请用 --sign '证书名' 重新编译，或在 Xcode 中设置自动签名。"
echo "真机 MetalANGLE 源文件保存在: $METALANGLE_DEVICE_FRAMEWORK"
if [[ "$BUILD_SIM" == "1" ]]; then
  echo "模拟器 MetalANGLE 源文件保存在: $METALANGLE_SIM_FRAMEWORK"
fi
