#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# MoePick 開発用ビルドスクリプト (Linux desktop)
# MoePick dev build script (Linux desktop only — for sandbox verification)
#
# WHY THIS SCRIPT EXISTS / 为什么需要这个脚本:
#   On Flutter 3.0 in this environment, `flutter build linux` silently fails to
#   produce build/linux/x64/<mode>/bundle/. Root cause: Flutter's Linux
#   CMakeLists.txt only redirects CMAKE_INSTALL_PREFIX to the bundle dir when
#   CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT is true; here CMake pre-seeds
#   the prefix to /usr/local, so artifacts land there instead of in bundle/.
#
#   在 Flutter 3.0 环境下 `flutter build linux` 会静默失败、不产出 bundle 目录。
#   根因: Flutter 的 Linux CMakeLists.txt 只在 CMAKE_INSTALL_PREFIX_INITIALIZED_
#   TO_DEFAULT 为真时才把安装前缀指到 bundle 目录; 本环境 CMake 已将其预置为
#   /usr/local, 导致产物被装到别处。
#
#   Workaround: run `flutter assemble` for the Dart side, then force the
#   install prefix via cmake and run `ninja install`.
#
# Usage: ./tool/build_linux.sh [debug|release]
# ---------------------------------------------------------------------------
set -euo pipefail

MODE="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export PUB_HOSTED_URL=https://pub.flutter-io.cn
export PUB_CACHE="${PUB_CACHE:-/opt/flutter/.pub-cache}"
export FLUTTER_ROOT=/opt/flutter

# Dart-side build (kernel snapshot + flutter_assets)
if [ "$MODE" = "release" ]; then
  BUILD_MODE="release"
else
  BUILD_MODE="debug"
fi

echo "==> [1/3] flutter assemble ($BUILD_MODE)"
flutter assemble \
  --no-version-check \
  --output=build \
  -dTargetPlatform=linux-x64 \
  -dBuildMode="$BUILD_MODE" \
  -dTargetFile=lib/main.dart \
  -dTreeShakeIcons="false" \
  "debug_bundle_linux-x64_assets" 2>&1 | tail -5 || true

BUILD_DIR="build/linux/x64/$BUILD_MODE"

echo "==> [2/3] cmake configure (install prefix -> bundle/)"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake . -DCMAKE_INSTALL_PREFIX="$ROOT/$BUILD_DIR/bundle" > /tmp/moepick_cmake.log 2>&1

echo "==> [3/3] ninja + ninja install"
ninja > /tmp/moepick_ninja.log 2>&1
ninja install > /tmp/moepick_install.log 2>&1

echo ""
echo "==> Build complete: $ROOT/$BUILD_DIR/bundle"
ls -1 "$ROOT/$BUILD_DIR/bundle"
