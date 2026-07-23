#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
output="${1:-/tmp/NumiAutomata-AppStore}"
temporary_root="$(mktemp -d -t numi-automata-store-assets)"
trap 'rm -rf "$temporary_root"' EXIT

mkdir -p "$output/Screenshots" "$output/AppIcon"

icon_source="$root/Packaging/AppIcon-master.png"
sips -s format jpeg -s formatOptions 100 "$icon_source" \
    --out "$temporary_root/AppIcon-flat.jpg" >/dev/null
sips -s format png -z 1024 1024 "$temporary_root/AppIcon-flat.jpg" \
    --out "$output/AppIcon/AppIcon-1024.png" >/dev/null

typeset -A captures
captures=(
    01-overview "$root/Docs/Media/numi-automata-overview.png"
    02-organisms "$root/Docs/Media/numi-automata-agents.png"
    03-cells "$root/Docs/Media/numi-automata-cells.png"
    04-ecology "$root/Docs/Media/numi-automata-ecology.png"
    05-wave "$root/Docs/Media/numi-automata-wave.png"
)

for name source in ${(kv)captures}; do
    working="$temporary_root/$name.png"
    flattened="$temporary_root/$name.jpg"
    cp "$source" "$working"
    width="$(sips -g pixelWidth "$working" | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$working" | awk '/pixelHeight/ { print $2 }')"
    target_height="$(( width * 10 / 16 ))"
    if (( target_height <= height )); then
        sips --cropToHeightWidth "$target_height" "$width" "$working" >/dev/null
    else
        target_width="$(( height * 16 / 10 ))"
        sips --cropToHeightWidth "$height" "$target_width" "$working" >/dev/null
    fi
    sips -s format jpeg -s formatOptions 100 "$working" \
        --out "$flattened" >/dev/null
    sips -s format png -z 1600 2560 "$flattened" \
        --out "$output/Screenshots/$name.png" >/dev/null
done

print "Prepared App Store assets: $output"
