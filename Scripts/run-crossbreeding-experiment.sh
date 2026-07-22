#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

swift build -c release --product NumiAutomata --jobs "${NUMI_SWIFT_JOBS:-1}"

# Sixteen separated pairs selected from the ordinary founder generator. Each
# pair has convergent initial motion, reciprocal recognition, low predatory
# investment, and no forced biological outcome. Fusion, junction persistence,
# division, and crossover remain decisions of the causal simulation.
exec .build/release/NumiAutomata experiment \
  --steps "${NUMI_STEPS:-12000}" \
  --seed "${NUMI_SEED:-424316}" \
  --batch "${NUMI_BATCH:-64}" \
  --sample-every "${NUMI_SAMPLE_EVERY:-250}" \
  --audit-every "${NUMI_AUDIT_EVERY:-100}" \
  --quantum-stride 3 \
  --founder 0.06436,0.100 --founder 0.06756,0.100 \
  --founder 0.11497,0.320 --founder 0.11817,0.320 \
  --founder 0.16577,0.540 --founder 0.16897,0.540 \
  --founder 0.21475,0.760 --founder 0.21795,0.760 \
  --founder 0.27009,0.100 --founder 0.27329,0.100 \
  --founder 0.33020,0.320 --founder 0.33340,0.320 \
  --founder 0.40052,0.540 --founder 0.40372,0.540 \
  --founder 0.44615,0.760 --founder 0.44935,0.760 \
  --founder 0.50689,0.100 --founder 0.51009,0.100 \
  --founder 0.57379,0.320 --founder 0.57699,0.320 \
  --founder 0.62501,0.540 --founder 0.62821,0.540 \
  --founder 0.71513,0.760 --founder 0.71833,0.760 \
  --founder 0.73876,0.100 --founder 0.74196,0.100 \
  --founder 0.82223,0.320 --founder 0.82543,0.320 \
  --founder 0.87145,0.540 --founder 0.87465,0.540 \
  --founder 0.90982,0.760 --founder 0.91302,0.760 \
  --output "${NUMI_OUTPUT:-Experiments/crossbreeding-seed-424316.jsonl}" \
  "$@"
