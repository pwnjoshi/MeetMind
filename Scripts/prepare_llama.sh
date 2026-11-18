#!/usr/bin/env bash
set -euo pipefail

# Official b12491 ships macOS/device slices only. Build the missing
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
python3 - "$WORK/base.zip" <<'PY'
import hashlib, pathlib, sys
archive = pathlib.Path(sys.argv[1])
assert hashlib.sha256(archive.read_bytes()).hexdigest() == "fa1be672f30bc5bb5cd887c734324b8d1538a13cf380bb197f78c1c06ba15011", "Native runtime checksum mismatch"
PY
# ditto preserves versioned macOS framework symlinks; zipfile.extractall does not.
ditto -x -k "$WORK/base.zip" "$WORK/base"
if [[ ! -d "$WORK/source/.git" ]]; then
    git init "$WORK/source"
    git -C "$WORK/source" remote add origin https://github.com/ggml-org/llama.cpp.git
fi
git -C "$WORK/source" fetch --depth 1 origin "$REVISION"
git -C "$WORK/source" checkout --detach FETCH_HEAD
test "$(git -C "$WORK/source" rev-parse HEAD)" = "$REVISION"
(
    cd "$WORK/source"
    bash build-xcframework.sh ios-sim
)
BASE="$WORK/base/build-apple/llama.xcframework"
SIMULATOR="$WORK/source/build-apple/llama.xcframework"
SIMULATOR_FRAMEWORK="$(python3 - "$SIMULATOR" <<'PY'
import pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1])
with (root / 'Info.plist').open('rb') as f:
    slices = plistlib.load(f)['AvailableLibraries']
simulator = next(s for s in slices if s['SupportedPlatform'] == 'ios' and s.get('SupportedPlatformVariant') == 'simulator')
print(root / simulator['LibraryIdentifier'] / simulator['LibraryPath'])
PY
)"
xcrun xcodebuild -create-xcframework \
    -framework "$BASE/macos-arm64_x86_64/llama.framework" \
    -framework "$BASE/ios-arm64/llama.framework" \
    -framework "$SIMULATOR_FRAMEWORK" \
    -output "$DEST"
python3 - "$DEST/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    slices = plistlib.load(f)['AvailableLibraries']
assert any(s['SupportedPlatform'] == 'ios' and s.get('SupportedPlatformVariant') == 'simulator' for s in slices)
print('Validated macOS, iPhone, and ARM64 iOS Simulator runtime slices')
PY
