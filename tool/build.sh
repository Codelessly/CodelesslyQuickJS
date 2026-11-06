#!/bin/bash
# Builds the native library for this machine, for tests on the Dart VM
# (flutter test) here and in codelessly_sdk. Apps get it from the Flutter
# plugin build instead.
#
# Usage: tool/build.sh [out dir]  ->  <out>/libcodelessly_quickjs.{so,dylib}
# The out dir defaults to .dart_tool/codelessly_quickjs in this package.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.dart_tool/codelessly_quickjs}"
mkdir -p "$OUT/build"
cmake -S "$ROOT/src" -B "$OUT/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$OUT/build" --parallel >/dev/null
for f in "$OUT/build"/libcodelessly_quickjs.so "$OUT/build"/libcodelessly_quickjs.dylib; do
  if [ -f "$f" ]; then cp "$f" "$OUT/"; fi
done
ls "$OUT"/libcodelessly_quickjs.*
