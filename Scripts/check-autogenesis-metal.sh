#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
air_file="$(mktemp -t autogenesis).air"
swift_log="$(mktemp -t autogenesis-swift).log"
swift_jobs="${NUMI_SWIFT_JOBS:-1}"
trap 'rm -f "$air_file" "$swift_log"' EXIT

run_swift_with_timestamp_retry() {
    : > "$swift_log"
    if "$@" 2>&1 | tee "$swift_log"; then
        return 0
    fi
    if ! /usr/bin/grep -q "was modified during the build" "$swift_log"; then
        return 1
    fi
    print -u2 "Xcode reported a coordinated-file timestamp race; retrying once clean."
    swift package clean
    "$@"
}

cd "$root"
xcrun -sdk macosx metal -std=metal3.2 \
    -c Sources/AutogenesisMetal/Shaders/Replicator.metal \
    -o "$air_file"
if [[ "${NUMI_SKIP_CLEAN:-0}" != "1" ]]; then
    swift package clean
fi
run_swift_with_timestamp_retry \
    swift build --product NumiAutomata --jobs "$swift_jobs"
run_swift_with_timestamp_retry swift test --jobs "$swift_jobs"
