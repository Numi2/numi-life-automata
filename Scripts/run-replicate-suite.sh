#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
STEPS="${NUMI_STEPS:-100000}"
SAMPLE_EVERY="${NUMI_SAMPLE_EVERY:-1000}"
BATCH="${NUMI_BATCH:-64}"
OUTPUT_DIR="${1:-$ROOT/Experiments/replicate-suite-$(date -u +%Y%m%dT%H%M%SZ)}"
SEEDS=(7331 10103 19001 29009 41011 53003 67003 79031)

mkdir -p "$OUTPUT_DIR"
cd "$ROOT"
swift build -c release

for seed in "${SEEDS[@]}"; do
    echo "numi_replicate_start seed=$seed steps=$STEPS"
    .build/release/NumiAutomata experiment \
        --seed "$seed" \
        --steps "$STEPS" \
        --sample-every "$SAMPLE_EVERY" \
        --batch "$BATCH" \
        --output "$OUTPUT_DIR/seed-$seed.jsonl"
done

echo "numi_replicate_suite_complete output=$OUTPUT_DIR"
