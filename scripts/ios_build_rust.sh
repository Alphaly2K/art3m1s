#!/usr/bin/env bash
set -euo pipefail

# ── iOS Rust 动态 Framework 编译脚本 ────────────────────────────────────
# 从 Rust 源码编译 cdylib，封装为 .framework bundle，输出到
# ios/Frameworks/ 供 CocoaPods vendored_frameworks 使用。
#
# 用法:
#   ./scripts/ios_build_rust.sh [--release] [--device-only] [--sign "证书名"]
#
# 前置条件:
#   1. Rust 工具链: rustup target add aarch64-apple-ios aarch64-apple-ios-sim
#   2. 环境变量 CORE_SRC / PFS_SRC 指向 Rust 项目目录（默认 ../art3m1s-core、../pfs-upk）

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$PROJECT_DIR/ios/Frameworks"

# ── 可配置: Rust 项目路径 ──────────────────────────────────────────────
CORE_SRC="${CORE_SRC:-$PROJECT_DIR/../art3m1s-core}"
PFS_SRC="${PFS_SRC:-$PROJECT_DIR/../pfs-upk}"

# ── 参数解析 ────────────────────────────────────────────────────────────
PROFILE="release"
CODE_SIGN_ID=""
BUILD_SIM=1

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
require plutil

# ── iOS targets ─────────────────────────────────────────────────────────
IOS_DEVICE_TARGET="aarch64-apple-ios"
IOS_SIM_TARGET="aarch64-apple-ios-sim"

check_target() {
  rustup target list --installed | grep -q "$1" || {
    echo "Rust target $1 未安装，正在安装..."
    rustup target add "$1"
  }
}

check_target "$IOS_DEVICE_TARGET"
if [[ "$BUILD_SIM" == "1" ]]; then
  check_target "$IOS_SIM_TARGET"
fi

# ── 生成 framework ──────────────────────────────────────────────────────
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

  echo "  -> $IOS_DEVICE_TARGET"
  cargo build "${CARGO_FLAGS[@]}" --lib \
    --manifest-path "$src_dir/Cargo.toml" \
    --target "$IOS_DEVICE_TARGET"

  if [[ "$BUILD_SIM" == "1" ]]; then
    echo "  -> $IOS_SIM_TARGET"
    cargo build "${CARGO_FLAGS[@]}" --lib \
      --manifest-path "$src_dir/Cargo.toml" \
      --target "$IOS_SIM_TARGET"
  fi

  local device_dylib="$src_dir/target/$IOS_DEVICE_TARGET/$TARGET_DIR_SUFFIX/lib${lib_name}.dylib"
  local sim_dylib="$src_dir/target/$IOS_SIM_TARGET/$TARGET_DIR_SUFFIX/lib${lib_name}.dylib"

  if [[ ! -f "$device_dylib" ]] && [[ ! -f "$sim_dylib" ]]; then
    echo "ERROR: $lib_name 编译产物缺失"
    exit 1
  fi

  local fw_dir="$OUT_DIR/${lib_name}.framework"
  rm -rf "$fw_dir"
  mkdir -p "$fw_dir"

  local fw_bin="$fw_dir/$lib_name"

  if [[ -f "$device_dylib" ]] && [[ -f "$sim_dylib" ]] && [[ "$BUILD_SIM" == "1" ]]; then
    echo "  -> lipo 合成 universal binary"
    lipo -create "$device_dylib" "$sim_dylib" -output "$fw_bin"
  elif [[ -f "$device_dylib" ]]; then
    echo "  -> 仅真机"
    cp "$device_dylib" "$fw_bin"
  else
    echo "  -> 仅模拟器"
    cp "$sim_dylib" "$fw_bin"
  fi

  # 移除 install_name（framework 不需要，由 dyld 处理）
  install_name_tool -id "@rpath/${lib_name}.framework/$lib_name" "$fw_bin" 2>/dev/null || true

  # ── Info.plist ──────────────────────────────────────────────────────
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
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>MinimumOSVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST

  # ── 代码签名 ────────────────────────────────────────────────────────
  if [[ -n "$CODE_SIGN_ID" ]]; then
    echo "  -> 签名: $CODE_SIGN_ID"
    codesign --force --sign "$CODE_SIGN_ID" --timestamp=none "$fw_dir"
  fi

  echo "  -> $fw_dir (${lib_name}.framework)"
}

# ── 编译 ────────────────────────────────────────────────────────────────
mkdir -p "$OUT_DIR"

make_framework "art3m1s_core" "$CORE_SRC" "moe.alphaly.art3m1s.core"
make_framework "pfs_upk"       "$PFS_SRC"  "moe.alphaly.art3m1s.pfs"

echo ""
echo "=== 完成 ==="
echo "Frameworks 已输出到: $OUT_DIR"
ls -lh "$OUT_DIR"/*.framework/*/..?* "$OUT_DIR"/*.framework/ 2>/dev/null | head -20 || true
echo ""
echo "若未签名，请用 --sign '证书名' 重新编译，或在 Xcode 中设置自动签名。"
echo "MetalANGLE.Framework 请手动放入 $OUT_DIR"
