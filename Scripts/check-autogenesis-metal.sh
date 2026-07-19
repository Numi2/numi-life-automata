#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
air_file="$(mktemp -t autogenesis).air"
trap 'rm -f "$air_file"' EXIT

cd "$root"
xcrun -sdk macosx metal -std=metal3.2 \
    -c Sources/AutogenesisMetal/Shaders/Replicator.metal \
    -o "$air_file"
swift build --product NumiAutomata --jobs 4
swift test --jobs 4
