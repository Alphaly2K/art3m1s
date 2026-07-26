#!/bin/bash
# 生成 .env.git（构建期注入的 GIT_COMMIT + APP_VERSION），供 flutter
# --dart-define-from-file=.env.git 注入（iOS/Xcode 构建等无法直接传 --dart-define 时）。
#   GIT_COMMIT  = git 提交短哈希（构建号）
#   APP_VERSION = pubspec 完整版本名（含 -0.2.0c 预发布后缀；绕开平台把
#                 CFBundleShortVersionString 截成纯数字导致丢 -/字母的问题）
# cd 到项目根，保证不论从哪调用都能读到 pubspec 并把 .env.git 写在根目录。
cd "$(dirname "$0")/.." || exit 1
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
VERSION=$(grep '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*//; s/\+.*$//')
{
  echo "GIT_COMMIT=$COMMIT"
  echo "APP_VERSION=$VERSION"
} > .env.git
echo "wrote .env.git: GIT_COMMIT=$COMMIT APP_VERSION=$VERSION"
