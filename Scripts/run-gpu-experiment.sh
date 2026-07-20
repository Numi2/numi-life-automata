#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"

cd "$ROOT"
swift build -c release --product NumiAutomata
exec "$ROOT/.build/release/NumiAutomata" experiment "$@"
