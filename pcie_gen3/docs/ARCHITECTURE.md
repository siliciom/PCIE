# PCIe Gen3 Testbench Architecture

## 1. Overview

The testbench models one PCIe link between a **Root Complex (RC)** and an
**Endpoint (EP)**, driven and checked end-to-end through the layered PCIe
stack:

```
 Transaction Layer (TL)  <-- TLPs -->  Transaction Layer (TL)
          |                                     |
 Data Link Layer (DLL)   <-- DLLPs -->  Data Link Layer (DLL)
          |                                     |
     MAC / LTSSM         <-- Ordered Sets -->     MAC / LTSSM
          |                                     |
   Physical (PMA/PIPE)   <-- serial bits -->   Physical (PMA/PIPE)
     RC side                                   EP side
```

The number of RC/EP instances and lanes are compile-time parameters
(`NUM_RC`, `NUM_EP`, `NUM_LANES` in `top/pcie_top_defines.svh`, set via
`+define+` on `vlog`). A single RC/EP pair with one lane is the default and
the only configuration currently driven by the base test.

## 2. Top Level (`top/`)

* **`PCIe_TOP.sv` / `TOP.sv`** - instantiate the RC and EP environments, the
  interfaces connecting them, and start `run_test()`.
* **Interfaces**:
  * `TX_TL_DL_Interface` / `RX_TL_DL_Interface` - TL <-> DLL handoff
  * `TX_DL_PCS_Interface` / `RX_DL_PCS_Interface` - DLL <-> MAC handoff
  * `TX_Pipe_interface` / `RX_Pipe_interface` - MAC <-> PMA (PIPE-style)
  * `Phy_Interface.sv` - per-lane serial bit stream between RC and EP PMA
  * `apb_interface.sv` - APB bus used for register-space (CFG) access
* **`Package.sv`** - top-level SystemVerilog package aggregating includes.
* **`PCIe_Enum_Type_Pkg.sv`** - shared enum/type package (TLP types, formats,
  LTSSM states, etc., alongside `pcie_top_defines.svh`).
* **`pcie_top_defines.svh` / `pcie_top_defines.sv`** - compile-time macros
  (`NUM_RC`, `NUM_EP`, `NUM_LANES`, `NUM_VC`) and shared enums, including
  `tlp_type_e` and `err_inject_e` (error-injection scenarios, see
  `KNOWN_ISSUES.md`).

## 3. Agents (`agents/`)

Each protocol layer has its own UVM agent (`*_Agent`/`*_agent`,
`*_Driver`, `*_Monitor`, `*_Sequencer`):

| Agent | Layer | Responsibility |
|---|---|---|
| `PCIe_TL_Agent` | Transaction | Drives/monitors TLPs (requests & completions) |
| `PCIe_DLL_Agent` | Data Link | Drives/monitors DLLPs, Ack/Nak, sequence numbers, replay buffer |
| `PCIe_MAC_Agent` | MAC / LTSSM | Drives/monitors the LTSSM state machine and Ordered Sets |
| `PCIe_PMA_Agent` | Physical | Serializes/deserializes the per-lane bit stream (`Phy_Interface`) |
| `apb_master_agent` / `apb_slv_agent` | Register access | Drives the APB bus used to reach `EP_Config_Space` |

Supporting (non-agent) components in `agents/`:

* **`EP_Config_Space.sv`** - models the Endpoint's PCI configuration space
  (BARs, command/status, etc.) reachable over APB.
* **`FC_Manager.sv`** (also referenced from `env/`) / **`TAG_Manager.sv`** -
  flow-control credit bookkeeping and outstanding-tag allocation used by the
  TL driver/sequences.
* **`VC_Arbiter.sv`** - Virtual Channel arbitration between TC-mapped traffic.
* **`RX_PCIe_LUT.sv`** - lookup table used on the receive path (e.g. for
  scrambling/byte-striping bookkeeping).

Each driver implements the **LTSSM** for its side (RC/EP): Detect -> Polling
-> Configuration -> L0, plus Recovery, Loopback, Hot Reset and Disabled
sub-states, all gated by timers pulled from `env_cfg` (see below).

## 4. Environment (`env/`)

`Env_Top.sv` instantiates and connects, per RC/EP side:

* `PCIe_TL_Agnt`, `PCIe_DLL_Agnt`, MAC/PMA agents, `Apb_Slave_Agnt`
* **Scoreboards**: `TL_Scoreboard.sv` (TL request/completion checking),
  `DL_Scoreboard.sv` (DLLP/sequence-number checking), `MAC_SB.sv`,
  aggregated under `Scoreboard_Top.sv`
* **Coverage**: `pcie_cov.sv` (TL-layer functional coverage), `DL_cov.sv`
  (DLL-layer coverage)
* **`Error_Report_Catcher.sv`** - intercepts expected `UVM_ERROR`/`UVM_FATAL`
  reports for negative/error-injection tests so they don't fail the test,
  re-tags them as `EXPECTED_<id>`, and counts them (see `KNOWN_ISSUES.md` for
  the demotion mechanism)
* **`reg_block.sv` / `reg_block1.sv`** - UVM RAL register model(s) for the
  Endpoint's configuration/register space
* **`adapter.sv`** - RAL-to-APB bus adapter (`apb_reg_adapter`) used by
  `pcie_ral_test`
* **`env_config.sv`** - the `env_cfg` object: RC/EP mode select, `gen`
  (speed), `num_lanes`/`active_lane_mask`, TC->VC mapping table,
  `inject_err` (error-injection selector), and every LTSSM sub-state timeout
  (`detect_quiet_timeout`, `polling_active_timeout`, `recovery_*_timeout`,
  etc.), each commented with the PCIe Base Spec bound it approximates.

TLM connections wire monitor analysis ports into the scoreboards and
coverage collectors, e.g.:

```
PCIe_TL_Agnt.TX_TL_Mon.TX_TL_Send.connect(TL_Scb.TX_TL_Recv);
PCIe_DLL_Agnt.PCIe_DLL_Mon.rc_tx.connect(DL_Scb.rc_tx_imp);
```

## 5. Sequences (`sequences/`)

* **`Sequence_item.sv`** - the TL transaction item (TLP fields: fmt, type,
  address, length, tag, TC, payload, etc.)
* **`Sequence.sv`** - TL-layer sequences building the TLP traffic patterns
  used by the functional tests (single/multiple/B2B reads & writes, max
  payload, randomized length, tag/TC-VC variants)
* **`apb_master_seq_item.sv` / `apb_slv_seq.sv` / `apb_slv_xtn.sv`** - APB
  sequence items/sequences for register-space access
* **`uvm_reg_sequence.sv` / `uvm_reg_sequence1.sv`** - RAL sequences used by
  `pcie_ral_test`

## 6. Tests (`tests/`)

`pcie_base_test` (in `tests/Test.sv`) builds `Env_Top` for both RC and EP,
applies `env_cfg`, and brings the link to `L0` before handing off to
`run_phase`. All functional and LTSSM tests extend it. `Error_Tests.sv`
contains error-injection tests, which extend `pcie_base_test` and set
`cfg.inject_err` to a specific `err_inject_e` scenario. See `docs/TESTS.md`
for the complete list and `docs/DEBUG_GUIDE.md` for how to run one.

## 7. Regression & Simulation (`Regression/`, `sim/`)

* **`run.do`** (in `pcie_gen3/`) - compiles and runs a single, fixed test
  (edit `+UVM_TESTNAME=` to change it).
* **`sim/regr.do`** - runs the full test list (defined inline as a Tcl
  `tests` list), merges coverage into `coverage_reports/merged_cov.ucdb`, and
  writes `sim/regression_summary.log` with a PASS/FAIL count and per-test
  seeds for reproduction.
* **`sim/run.do`** - single-test run with code coverage enabled, writing to
  `coverage_reports_single/`.
* **`sim/coverage_reports/`** - per-test `.ucdb` coverage databases plus
  merged coverage and text logs.
* **`sim/sim/<test_name>/<test_name>.log`** - full simulation transcript per
  test, including all `uvm_info`/`uvm_error` output.
