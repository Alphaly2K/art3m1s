#!/usr/bin/env bash
# 以 git 提交短哈希作为「构建号」注入 flutter（--dart-define=GIT_COMMIT），
# 关于页会显示成「版本 1.1.0-0.2.0c (a1b2c3d)」。构建号不写进 pubspec。
#
# 用法（默认 run）：
#   tool/run.sh                 # 等价 flutter run
#   tool/run.sh build macos     # 等价 flutter build macos
#   tool/run.sh run -d macos    # 透传任意 flutter 参数
set -euo pipefail
cd "$(dirname "$0")/.."
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
# 完整版本名（含 -0.2.0c 预发布后缀）从 pubspec 取，避免平台截断 CFBundleShortVersionString。
VERSION="$(grep '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*//; s/\+.*$//')"
if [ "$#" -eq 0 ]; then set -- run; fi
exec flutter "$@" \
  --dart-define=GIT_COMMIT="$COMMIT" \
  --dart-define=APP_VERSION="$VERSION"
