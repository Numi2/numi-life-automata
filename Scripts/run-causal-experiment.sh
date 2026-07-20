#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

swift build -c release --product NumiAutomata --jobs "${NUMI_SWIFT_JOBS:-1}"
exec .build/release/NumiAutomata causal-experiment "$@"
