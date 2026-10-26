# CPU topology fixtures

These are synthetic compatibility inputs, not measurements taken on M5/M6 hardware.
They use the official macmon 0.10.0 `SocInfo.cpu_tiers`, `Metrics.cpu_tiers` and `vm` JSON schema.

- `m6.json`: 6 E + 4 P + 2 S, using the tier frequencies and active ratios in upstream
  `src/metrics.rs::samples_the_three_cpu_tiers_of_m6`. Frequency ceilings are test values.
- `m5.json`: E/S; `m5-pro.json`: P/S. Counts, frequencies and utilization are test values.
- `vm.json`: one unknown (`_`) tier; no power, GPU, frequency or temperature telemetry.

The deprecated ecpu/pcpu fields deliberately represent only the lowest/highest tiers.
Tests verify that the middle P tier is preserved and that canonical-only inputs also work.
Runtime testing is performed separately on an Apple M4.
