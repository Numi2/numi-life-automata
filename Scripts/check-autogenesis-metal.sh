#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
air_file="$(mktemp -t autogenesis).air"
swift_jobs="${NUMI_SWIFT_JOBS:-1}"
trap 'rm -f "$air_file"' EXIT

cd "$root"
xcrun -sdk macosx metal -std=metal3.2 \
    -c Sources/AutogenesisMetal/Shaders/Replicator.metal \
    -o "$air_file"
if [[ "${NUMI_SKIP_CLEAN:-0}" != "1" ]]; then
    swift package clean
fi
swift build --product NumiAutomata --jobs "$swift_jobs"
swift test --jobs "$swift_jobs"
