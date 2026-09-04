# PCIe Gen3 Test List

All tests below extend `pcie_base_test` (`tests/Test.sv`), which brings the
RC<->EP link up to `L0` in `build_phase`/pre-run before the test's own
`run_phase` starts driving traffic. Functional tests live in `tests/Test.sv`;
protocol error-injection tests live in `tests/Error_Tests.sv`.

## Running a Test

```tcl
# pcie_gen3/run.do compiles with NUM_RC=1, NUM_EP=1 and launches a fixed test.
# Edit the +UVM_TESTNAME= line, or override on the vsim command line:
vsim work.PCIe_top +UVM_TESTNAME=<test_name> +UVM_VERBOSITY=UVM_LOW
```

To run the whole list with automated PASS/FAIL summary and merged coverage:

```tcl
# from pcie_gen3/sim/
vsim -c -do "set regression_name regr_cov1; set enable_cov 1; do regr.do"

# single test through the regression script (keeps its coverage/summary flow):
vsim -c -do "set regression_name single_test; set enable_cov 1; \
              set single_test <test_name>; do regr.do"
```

Seeds are randomized per run unless `set seed <n>` is passed before `regr.do`
(or `-sv_seed <n>` directly to `vsim`). `sim/regression_summary.log` records
the seed used for every test in the last run, for reproduction.

## Functional Tests (`tests/Test.sv`)

### Basic Memory / IO Read-Write

| Test | Description |
|---|---|
| `Single_Mem_Wr_Rd_3DW_test` | One 3DW-header Memory Write followed by a Memory Read |
| `Single_Mem_Wr_Rd_4DW_test` | Same, with 4DW (64-bit addressing) header |
| `Multiple_Mem_Wr_Rd_3DW_test` | Multiple back-to-back 3DW Mem Wr/Rd pairs |
| `Multiple_Mem_Wr_Rd_4DW_test` | Multiple back-to-back 4DW Mem Wr/Rd pairs |
| `B2B_Mem_Wr_Rd_3DW_test` | Back-to-back (no gap) 3DW Mem Wr/Rd |
| `B2B_Mem_Wr_Rd_4DW_test` | Back-to-back (no gap) 4DW Mem Wr/Rd |
| `Single_IO_Wr_Rd_3DW_test` | Single IO Write/Read (Length must be 1 DW per spec) |
| `Multiple_IO_Wr_Rd_3DW_test` | Multiple IO Wr/Rd transactions |
| `B2B_IO_Wr_Rd_3DW_test` | Back-to-back IO Wr/Rd transactions |
| `Single_Mem_Wr_emt_Rd_3DW_test` | Single Mem Write with an empty/zero-length Read |

### Payload / Length Variants

| Test | Description |
|---|---|
| `Single_Mem_Wr_Rd_3DW_Max_payload_test` | Single 3DW transaction at maximum payload size |
| `Single_Mem_Wr_Rd_4DW_Max_payload_test` | Single 4DW transaction at maximum payload size |
| `Multiple_Mem_Wr_Rd_3DW_rand_length_test` | Multiple 3DW transactions with randomized length |
| `Multiple_Mem_Wr_Rd_4DW_rand_length_test` | Multiple 4DW transactions with randomized length |

### Tag / Traffic-Class Variants

| Test | Description |
|---|---|
| `Multiple_Mem_Wr_Rd_3DW_tag_outstanding_test` | Multiple outstanding reads exercising tag allocation/tracking (`TAG_Manager`) |
| `Multiple_Mem_Wr_Rd_3DW_tc_vc_test` | Traffic exercising the TC->VC mapping table and `VC_Arbiter` |

### LTSSM / Link Training

| Test | Description |
|---|---|
| `LTSSM_Disabled_test` | Link Disable bit assertion -> `DISABLED` state and recovery |
| `LTSSM_Loopback_test` | Loopback entry, active, and exit sequence |
| `LTSSM_HotReset_test` | Hot Reset entry and link re-training |

### Register Access

| Test | Description |
|---|---|
| `pcie_ral_test` | Exercises the UVM RAL register model (`reg_block`/`reg_block1`) over the APB adapter against `EP_Config_Space` |

## Error-Injection Tests (`tests/Error_Tests.sv`)

Each test sets `cfg.inject_err` to one `err_inject_e` value (defined in
`top/pcie_top_defines.svh`) and confirms the DUT/environment reacts as
expected (error reported and, where applicable, demoted/counted by
`Error_Report_Catcher`, see `DEBUG_GUIDE.md`).

### Transaction Layer (TL) Errors

| Test | Injected Condition |
|---|---|
| `TL_ECRC_Error_test` | Corrupted ECRC on a TLP |
| `TL_Length_Mismatch_test` | Header `Length` field lies about DWs actually sent (Malformed/Fatal) |
| `TL_IO_Length_test` | IO Rd/Wr with `Length > 1` (spec requires `Length == 1`) |
| `TL_CFG_Length_test` | Config Rd/Wr with `Length > 1` (spec requires `Length == 1`) |
| `TL_Fmt_Rtype_Illegal_test` | Reserved `fmt`/`type` encoding |
| `TL_Bad_BE_test` | Non-contiguous first/last Byte-Enable pattern |
| `TL_EP_Poison_test` | EP (poison) bit set on an otherwise normal write |
| `TL_Unsupported_Request_test` | Address outside any implemented BAR range |
| `TL_Completer_Abort_test` | Completion carrying an unexpected/unallocated tag |

### Data Link Layer (DLL) Errors

| Test | Injected Condition |
|---|---|
| `DLL_LCRC_Error_test` | Corrupted LCRC on a TLP |
| `DLL_DLLP_CRC_Error_test` | Corrupted 16-bit CRC field of a DLLP |
| `DLL_Seq_Num_test` | Forced skip/out-of-order DLL sequence number |
| `DLL_Replay_Num_Rollover_test` | Repeated NAKs forcing the same sequence to replay 4+ times |
| `DLL_Replay_Timer_test` | Ack withheld past the replay timer limit |

## Notes

* `NUM_RC`/`NUM_EP` are compile-time `+define+` on `vlog`, not runtime
  `+plusargs` - only `NUM_RC=1 NUM_EP=1` is exercised by the base test today.
  See `KNOWN_ISSUES.md`.
* Full-regression PASS/FAIL and per-test seeds are recorded in
  `sim/sim/regression_summary.log`.

