# Known Issues & Limitations

This list is drawn from open `TODO`s and documented modeling shortcuts in the
current codebase (mainly `agents/PCIe_MAC_Driver.sv` and
`env/env_config.sv`). None of these currently fail the recorded regression
(`sim/sim/regression_summary.log`: 33/33 PASS), but they're worth knowing
about before relying on exact LTSSM timing or multi-instance configurations.

## 1. Multi-RC / Multi-EP Is Built but Not Driven

`run.do` documents this directly:

> If `NUM_RC > 1`, instances `RC_Env[1..N]` are built and reach link-up but
> are not driven by the base test - extend `run_phase` to drive them.

`NUM_RC`/`NUM_EP`/`NUM_LANES` are compile-time `` `define ``s
(`top/pcie_top_defines.svh`), not runtime `+plusargs`, and only
`NUM_RC=1 NUM_EP=1` (single lane.


