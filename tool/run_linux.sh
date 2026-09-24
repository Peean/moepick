#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Run the built Linux bundle headlessly (sandbox verification helper).
# 在无显示器环境下运行已构建的 Linux 产物（沙箱验证用）。
#
# Usage: ./tool/run_linux.sh [seconds]
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/debug/bundle"
DURATION="${1:-20}"

if [ ! -x "$BUNDLE/moepick" ]; then
  echo "Bundle not found. Run ./tool/build_linux.sh first." >&2
  exit 1
fi

cd "$BUNDLE"
# xvfb-run provides a virtual X display in headless environments.
# xvfb-run 在无显示器环境下提供虚拟 X display。
timeout "$DURATION" xvfb-run -a -s "-screen 0 1280x900x24" ./moepick
