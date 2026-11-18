#!/usr/bin/env bash
set -euo pipefail

# Official b12491 ships macOS/device slices only. Build the missing ARM64
# simulator slice from that exact release, preserving the device binary tested.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/NativeLlama"
DEST="$ROOT/OfflineEngineKit/Artifacts/llama.xcframework"
REVISION=8c16babba5d4c66e28a19d86e572e4b04f522d52
mkdir -p "$WORK" "$(dirname "$DEST")"
if [[ -f "$DEST/Info.plist" ]]; then
    echo "Using cached llama runtime with simulator support"
    exit 0
fi
curl --fail --location --retry 3 \
    https://github.com/ggml-org/llama.cpp/releases/download/b12491/llama-b12491-xcframework.zip \
    --output "$WORK/base.zip"
python3 - "$WORK/base.zip" "$WORK/base" <<'PY'
import hashlib, pathlib, sys, zipfile
archive = pathlib.Path(sys.argv[1])
assert hashlib.sha256(archive.read_bytes()).hexdigest() == "fa1be672f30bc5bb5cd887c734324b8d1538a13cf380bb197f78c1c06ba15011", "Native runtime checksum mismatch"
with zipfile.ZipFile(archive) as package:
    package.extractall(sys.argv[2])
PY
if [[ ! -d "$WORK/source/.git" ]]; then
    git init "$WORK/source"
    git -C "$WORK/source" remote add origin https://github.com/ggml-org/llama.cpp.git
fi
git -C "$WORK/source" fetch --depth 1 origin "$REVISION"
git -C "$WORK/source" checkout --detach FETCH_HEAD
test "$(git -C "$WORK/source" rev-parse HEAD)" = "$REVISION"
python3 - "$WORK/source/build-xcframework.sh" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = '-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"'
assert needle in s, "Upstream simulator build flags changed"
# The CI simulator runs ARM64. Avoid building an unused Intel simulator slice.
p.write_text(s.replace(needle, '-DCMAKE_OSX_ARCHITECTURES="arm64"', 1))
PY
(
    cd "$WORK/source"
    bash build-xcframework.sh ios-sim
)
BASE="$WORK/base/build-apple/llama.xcframework"
xcrun xcodebuild -create-xcframework \
    -framework "$BASE/macos-arm64_x86_64/llama.framework" \
    -framework "$BASE/ios-arm64/llama.framework" \
    -framework "$WORK/source/build-apple/llama.xcframework/ios-arm64-simulator/llama.framework" \
    -output "$DEST"
python3 - "$DEST/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    slices = plistlib.load(f)['AvailableLibraries']
assert any(s['SupportedPlatform'] == 'ios' and s.get('SupportedPlatformVariant') == 'simulator' for s in slices)
print('Validated macOS, iPhone, and ARM64 iOS Simulator runtime slices')
PY
