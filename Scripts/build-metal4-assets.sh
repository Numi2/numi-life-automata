#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
shader="$root/Sources/AutogenesisMetal/Shaders/Replicator.metal"
metallib="$root/Sources/AutogenesisMetal/Shaders/Replicator.metallib"
pipeline_script="$root/Sources/AutogenesisMetal/Shaders/Replicator.mtl4-json"
archive="$root/Sources/AutogenesisMetal/Shaders/Replicator.mtl4archive"
temporary_root="$(mktemp -d -t numi-metal4-assets)"
air="$temporary_root/Replicator.air"
compiled="$temporary_root/Replicator.metallib"
translated_script="$temporary_root/Replicator.mtl4-json"
compiled_archive="$temporary_root/Replicator.mtl4archive"

trap 'rm -rf "$temporary_root"' EXIT

xcrun -sdk macosx metal -std=metal4.0 -c "$shader" -o "$air"
xcrun -sdk macosx metallib "$air" -o "$compiled"
sed -E \
    "s#\"path\": \"[^\"]*Replicator.metallib\"#\"path\": \"$compiled\"#" \
    "$pipeline_script" > "$translated_script"
xcrun -sdk macosx metal-tt \
    "$compiled" "$translated_script" -o "$compiled_archive"
mv "$compiled" "$metallib"
mv "$compiled_archive" "$archive"

print "Metal 4 shader library: $metallib"
print "Metal 4 pipeline archive: $archive"
