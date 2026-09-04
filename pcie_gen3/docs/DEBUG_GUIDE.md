# Debug Guide

## 1. Where to Look First

| What happened | Where |
|---|---|
| Full regression ran | `pcie_gen3/sim/sim/regression_summary.log` - PASS/FAIL count, list of failed tests, and the seed each test ran with |
| One test's full transcript | `pcie_gen3/sim/sim/<test_name>/<test_name>.log` |
| Coverage for one test | `pcie_gen3/sim/coverage_reports/<test_name>.ucdb` |
| Merged coverage | `pcie_gen3/sim/coverage_reports/merged_cov.ucdb`, text summaries in `coverage.log` / `detailed_coverage.log` |

Every `<test_name>.log` ends with a per-tag message-count table (from UVM's
built-in report summary) and a final `# Errors: N, Warnings: N` line - check
that line first.

## 2. Reproducing a Specific Failure

Seeds are recorded per test in `regression_summary.log` under `TEST SEEDS
(test:seed)`. Re-run the exact same stimulus with:

```tcl
vsim work.PCIe_top +UVM_TESTNAME=<test_name> -sv_seed <seed> \
     +UVM_VERBOSITY=UVM_LOW
```

or, through the regression script:

```tcl
vsim -c -do "set regression_name single_test; set enable_cov 1; \
              set single_test <test_name>; set seed <seed>; do regr.do"
```

## 3. Verbosity and Log Tags

Two `uvm_info` verbosity levels are used throughout the environment:

* **`UVM_LOW`** - meaningful, data-carrying messages: transaction contents,
  key protocol/state transitions with the values that drove them. These are
  the ones worth reading to understand *what happened*.
* **`UVM_HIGH`** - everything else: generic markers, byte/word-level trace,
  and high-volume per-symbol logging. Useful for deep debug but noisy for a
  first pass.

Run with `+UVM_VERBOSITY=UVM_LOW` for a normal pass/fail check, and bump to
`+UVM_VERBOSITY=UVM_HIGH` (or set it on a specific component via
`set_report_verbosity_level_hier` / `uvm_config_db` on that component's
`recording_detail`/verbosity) when you need to see everything from one
sub-block without flooding the log from the whole testbench.

Common log ID tags (the first argument to `` `uvm_info ``) you'll see, and
what they mean:

| Tag | Component | Covers |
|---|---|---|
| `RX_LTSSM` / `TX_LTSSM` | `PCIe_MAC_Driver` | LTSSM state entry/exit and sub-state timeout events, RC and EP side |
| `MAC_TX_DRV` / `MAC_RX_DRV` | `PCIe_MAC_Driver` | Ordered-set and DLLP/TLP framing on the MAC layer |
| `PIPE_DRV` | `PCIe_MAC_Driver` | PIPE-interface-level byte striping/scrambling |
| `MAC_TX` / `MAC_RX` / `MAC_RX_MON` / `MAC_TX_MON` | `PCIe_MAC_Monitor` | Passive capture of MAC-layer traffic (both directions) |
| `TX_TL_Driver` / `RX_TL_DRIVER` | `PCIe_TL_Driver` | TL-layer completion/queueing activity |
| `TL_Scoreboard`, `WRITE_TX_TL_Scoreboard`, `WRITE_RX_TL_Scoreboard`, `TL_Scoreboard_REQ`, `TL_Scoreboard_CPL` | `TL_Scoreboard` | Expected-vs-actual TLP checking |
| `DBG`, `UVM_DBG`, `SEQ`, `SEQUENCE` | `Sequence.sv` | Sequence-generated TLP fields and tag allocation |
| `SB`, `SB12`, `SB_REPORT` | Scoreboards | Waiting-for/summary messages |
| `EXPECTED_<id>` | `Error_Report_Catcher` | An error-injection test's *expected* error, demoted from `UVM_ERROR`/`UVM_FATAL` so it doesn't fail the test (see below) |

## 4. Debugging an Error-Injection Test

Error tests (`tests/Error_Tests.sv`) set `cfg.inject_err` to a scenario from
`err_inject_e` (`top/pcie_top_defines.svh`) and expect the environment to
*detect* the injected fault, not to run clean. `Error_Report_Catcher.sv`
intercepts the expected `UVM_ERROR`/`UVM_FATAL`, re-tags it
`EXPECTED_<id>`, and counts it instead of letting it fail the test.

If an error test fails:

1. Grep the log for `EXPECTED_` - if the count is `0`, the fault was never
   detected (check the injection actually took effect: one-shot scenarios
   like `ERR_LCRC`/`ERR_DLLP_CRC`/`ERR_SEQ_NUM`/`ERR_STP` are consumed and
   reset to `ERR_NONE` the next time that code path runs, so a race can
   cause them to be "missed").
2. If you instead see an *unrelated* `UVM_ERROR`/`UVM_FATAL` (not
   `EXPECTED_*`), that's a real regression, not the injected condition.
3. Confirm which side's `cfg` the test set - injection is per-driver
   (`RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg`, etc.), so direction
   (RC->EP vs EP->RC) depends on which handle was touched.

## 5. Debugging a Scoreboard Mismatch

`TL_Scoreboard`/`DL_Scoreboard`/`MAC_SB` log both the received transaction
and the queue state at the point of comparison (tag/key `%0h`, queue
`.size()`) at `UVM_LOW`. Search the log for the scoreboard tag
(`TL_Scoreboard_REQ`, `TL_Scoreboard_CPL`, `WRITE_TX_TL_Scoreboard`,
`WRITE_RX_TL_Scoreboard`) around the failure to see the exact key used and
whether the matching item was queued on the other side.

## 6. Debugging Link Training (LTSSM) Hangs

If a test times out before reaching `L0`:

1. Filter the log on `RX_LTSSM`/`TX_LTSSM` to see the last state entered on
   each side.
2. Check `env_cfg` timeouts (`detect_quiet_timeout`, `polling_active_timeout`,
   `config_*_timeout`, `recovery_*_timeout`, ...) - these are shortened from
   the PCIe Base Spec bounds by default for simulation turnaround; a real
   corner case near a spec boundary may need the spec value temporarily
   restored via `uvm_config_db` in the test.
3. See `KNOWN_ISSUES.md` - several LTSSM entry conditions are modeled as
   simplified single-event checks rather than the full multi-consecutive-TS
   matching the spec requires, which can shift exact transition timing.

## 7. Waveforms

`run.do` / `regr.do` run with `add log -r /*` (or `-coverage -debugDB`
equivalents), so a saved dataset is available for `vsim -view` /
`dataset open` post-run waveform debug alongside the text log, without
re-running the simulation.
