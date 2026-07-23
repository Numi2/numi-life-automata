#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
if [[ -n "${NUMI_RELEASE_ROOT:-}" ]]; then
    release_root="$NUMI_RELEASE_ROOT"
else
    release_root="$(mktemp -d -t numi-automata-app-store)"
fi
archive_path="$release_root/NumiAutomata.xcarchive"
export_path="$release_root/Export"

if [[ ! -s "$root/Sources/AutogenesisMetal/Shaders/Replicator.metallib" ||
      ! -s "$root/Sources/AutogenesisMetal/Shaders/Replicator.mtl4archive" ]]; then
    print -u2 "error: compiled Metal assets are missing; run Scripts/build-metal4-assets.sh"
    exit 1
fi

mkdir -p "$release_root"
cd "$root"
xcodegen generate

xcodebuild archive \
    -project NumiAutomata.xcodeproj \
    -scheme NumiAutomata \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    -allowProvisioningUpdates

codesign --verify --deep --strict \
    "$archive_path/Products/Applications/Numi Automata.app"

xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$root/Config/ExportOptions-AppStoreConnect.plist" \
    -allowProvisioningUpdates

print "Uploaded Numi Automata 1.0 (2) to App Store Connect."
