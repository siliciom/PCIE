# PCIe Gen1/2/3 UVM Verification Environment

A self-contained SystemVerilog/UVM verification environment for the **PCI Express Base 3.0**
protocol stack (Transaction, Data Link and Physical/LTSSM layers, plus configuration-space
enumeration).

> **There is no external RTL DUT.** Both link partners — the **Root Complex (RC)** and the
> **Endpoint (EP)** — are behavioural UVM models built out of the agents in `pcie_gen3/agents/`.
> `PCIe_top` (in `pcie_gen3/top/TOP.sv`) simply instantiates the interfaces, wires the RC PHY TX
> to the EP PHY RX (and vice-versa) as a serial loopback, and calls `run_test()`. The thing being
> "verified" is therefore the protocol behaviour modelled in the agents and checked by the
> scoreboards.

---

## 1. Prerequisites

| Need | Detail |
|---|---|
| Simulator | **Siemens QuestaSim / ModelSim** with SystemVerilog + UVM. Developed and run on **QuestaSim 2025.2**; anything from ~2021.1 onward should work. |
| UVM | **UVM 1.1d** — the version **built into QuestaSim** is used (`import uvm_pkg::*` resolves to `<questa>/uvm-1.1d`). No separate UVM install or `UVM_HOME` needed. |
| OS | Developed on Windows 11. The flow is plain `vlib`/`vlog`/`vsim` and works on Linux too (adjust the `vsim.exe` calls in the `.do` scripts to `vsim`). |
| Shell | The `.do` files are TCL run by `vsim -do`. Nothing else is required. |
| PATH | `vlib`, `vlog`, `vsim` (and on Windows `vsim.exe`) must be on `PATH`. |

Check your tool is visible:

```
vsim -version
```

---

## 2. Get the code

```
git clone <this-repo-url>
cd <repo>/pcie_gen3/sim
```

All simulation is driven from **`pcie_gen3/sim/`**. The `.do` scripts assume that is the current
directory and refer to the source as `../top/Package.sv ../top/TOP.sv`.

---

## 3. Quick start — run one test

From `pcie_gen3/sim/`:

```
vsim -c -do "set only Single_Mem_Wr_Rd_4DW_test; do run_all.do"
```

This compiles the whole environment once, then runs the single named test in batch mode.
When it finishes:

* transcript ............ `pcie_gen3/sim/sim/Single_Mem_Wr_Rd_4DW_test/Single_Mem_Wr_Rd_4DW_test.log`
* one-line result ....... printed to the console and written to `pcie_gen3/sim/sim/regression_summary.log`

A single test takes roughly **5–8 minutes** (most of it is LTSSM link training, ~290 µs of sim
time at Gen1).

### Run it in the GUI instead

```
vsim -do run.do
```

`run.do` compiles, loads one hard-coded test (`+UVM_TESTNAME=...` near the bottom — edit it),
adds all signals to the wave database (`add log -r /*`) and runs. Use this when you want waveforms.
(`pcie_gen3/run.do` is an older duplicate of `pcie_gen3/sim/run.do` — use the one in `sim/`.)

### Iterating on one test (compile once, re-run many)

```
cd pcie_gen3/sim
vlib work && vmap work work
vlog -work work -sv +define+NUM_RC=1 +define+NUM_EP=1 +define+NUM_RC_GEN=1 +define+NUM_EP_GEN=1 ../top/Package.sv ../top/TOP.sv
# then, as many times as you like:
vsim -c work.PCIe_top +UVM_TESTNAME=<test> +UVM_VERBOSITY=UVM_LOW -l my.log -do "run -all; quit -f"
```

---

## 4. Run the full regression

From `pcie_gen3/sim/`:

```
vsim -c -do run_all.do
```

* Compiles **once**.
* Runs **all 30 tests back-to-back**, each in its **own child `vsim`** (UVM calls `$finish` at the
  end of every test, which ends that simulation — so each test must be a fresh process). `exec`
  blocks until each child exits, so tests run strictly one after another; a crash or `UVM_FATAL`
  in one test does **not** abort the regression.
* Per-test transcript ... `pcie_gen3/sim/sim/<test_name>/<test_name>.log`
* Overall result ........ `pcie_gen3/sim/sim/regression_summary.log`

Expect the full Gen1 regression to take **~3 hours** (the last recorded run: 11 401 s for 30 tests).

### Options

Set any of these before `do run_all.do` (or pass `-gvar`):

| Variable | Default | Meaning |
|---|---|---|
| `regression_name` | `regr_all` | label written into the summary |
| `gen` | `1` | advertised PCIe generation: **1 / 2 / 3** (compiled in as `NUM_RC_GEN` / `NUM_EP_GEN`) |
| `verbosity` | `UVM_LOW` | per-test `+UVM_VERBOSITY` |
| `only` | `""` | run just one test by name |
| `stop_on_fail` | `0` | `1` = abort the regression at the first failing test |

Examples:

```
# Full regression at Gen3
vsim -c -do "set gen 3; set regression_name regr_gen3; do run_all.do"

# Just the memory tests, stop at first failure
vsim -c -do "set stop_on_fail 1; do run_all.do"   ;# (edit the `tests {}` list in run_all.do to subset)
```

### The older script

`pcie_gen3/sim/regr.do` is the original regression runner (also collects merged coverage).
`run_all.do` is a cleaner rewrite of the same idea; use whichever you prefer.
`regr.do`: `vsim -c -do "set regression_name regr_cov1; set enable_cov 1; do run.do"` — note it
`source`s `run.do` internally in that invocation form; read the header of `regr.do` for details.

---

## 5. Choosing the link speed (Gen1 / Gen2 / Gen3)

The generation is a **compile-time** parameter (`ifdef` macros are resolved by `vlog`, not `vsim`):

```
vlog ... +define+NUM_RC_GEN=3 +define+NUM_EP_GEN=3 ...
```

`run_all.do` does this for you via `set gen 3`. In `TOP.sv` the LTSSM always brings the link up at
**Gen1 (2.5 GT/s)** first, then — if the advertised generation is higher — steps up through
`Recovery.RcvrLock → RcvrCfg → Speed` one generation at a time (Gen1 → Gen2 → Gen3). The PIPE clock
(`RC_PCLK` / `EP_PCLK`) is muxed to 250 / 500 / 1000 MHz by the `Rate` pin the MAC driver drives.

**Note:** the physical layer is modelled as **128b/130b** (Gen3 encoding) at all speeds — 8b/10b for
Gen1/Gen2 is a stub. Gen3 equalization (`Recovery.Equalization`) is not implemented; the link changes
rate without it.

---

## 6. Directory layout

```
pcie_gen3/
  top/            Testbench top, interfaces, the compiled package and macros
    Package.sv        `include`s every class file (single compilation unit)
    TOP.sv            module PCIe_top: interfaces, PHY loopback, config_db, run_test()
    pcie_top_defines.svh   NUM_RC / NUM_EP / NUM_*_GEN / NUM_LANES / NUM_VC, TLP/err enums
    apb_defines.svh        APB ADDR_WIDTH / DATA_WIDTH
    *_Interface.sv         TL<->DL, DL<->PCS, PIPE, PHY, APB interfaces
  agents/         One agent per protocol layer, each with RC_MODE and EP_MODE behaviour
    PCIe_TL_*         Transaction Layer  (TLP build / capture / malformed checks)
    PCIe_DLL_*        Data Link Layer    (seq no, LCRC, Ack/Nak, replay buffer/timer, FC DLLPs)
    PCIe_MAC_*        MAC / LTSSM        (Detect..L0..Recovery..Loopback..HotReset..Disabled, TS1/TS2, striping)
    PCIe_PMA_*        PMA                (per-lane 130-bit serialise / deserialise, scrambling)
    RX_PCIe_LUT.sv    EP address decode + completion generation (UR / CA / split completions)
    EP_Config_Space.sv  EP Type-0 config space model + BAR sizing
    TAG_Manager.sv      outstanding-tag allocator
    VC_Arbiter.sv       strict-priority arbitration across 8 VCs
    apb_*               APB master/slave agents (register access path for the RAL)
  env/
    Env_Top.sv          builds one layer stack (TL+DLL+MAC+PMA + LUT + FC + cov)
    env_config.sv       env_cfg: mode (RC/EP), gen, num_lanes, LTSSM timeouts
    Scoreboard_Top.sv   end-to-end TLP transport check + memory-model read-data check
    DL_Scoreboard.sv    RC<->EP DLP / DLLP transport check
    MAC_SB.sv           PHY-word (post-stripe/scramble) transport check
    TL_Scoreboard.sv    pairs TL requests/completions, forwards to Scoreboard_Top
    FC_Manager.sv       per-VC flow-control credit accounting
    Error_Report_Catcher.sv   demotes an *expected* uvm_error to info for negative tests
    pcie_cov.sv         TLP functional coverage
    reg_block.sv / reg_block1.sv / adapter.sv   UVM RAL model over APB
  sequences/
    Sequence_item.sv    the PCIe TLP transaction (+ debug helpers: convert2string, pkt_uid, ...)
    Sequence.sv         Single/Multiple/B2B Mem & IO Wr/Rd sequences, Cfg Rd/Wr, Error_Inject_Seq
  tests/
    Test.sv             pcie_base_test (link-up + enumeration) and the functional tests
    Error_Tests.sv      the negative / error-injection tests
  Regression/         (regression guidelines / placeholder)
  config/            (placeholder)
  docs/             Extra documentation - see below
  sim/              << run everything from here >>
    run_all.do         recommended regression runner  (all tests, sequential)
    regr.do            original regression runner (+ coverage merge)
    run.do             single test in the GUI (with waveforms)
    sim/               per-test transcripts + regression_summary.log  (generated)
    coverage_reports/  per-test .ucdb + merged_cov.ucdb                (generated)
    work/              compiled library                                (generated, git-ignored)
```

### Supporting documentation

| File | Contents |
|---|---|
| [`pcie_gen3/docs/ARCHITECTURE.md`](pcie_gen3/docs/ARCHITECTURE.md) | Layer stack, agent roles, data flow RC→EP, scoreboard topology |
| [`pcie_gen3/docs/TESTS.md`](pcie_gen3/docs/TESTS.md) | Every test: what it drives, what it checks, expected result |
| [`pcie_gen3/docs/DEBUG_GUIDE.md`](pcie_gen3/docs/DEBUG_GUIDE.md) | Message-ID map, verbosity tiers, `+PCIE_DEBUG`, tracing one packet, reading scoreboard diffs |
| [`pcie_gen3/docs/KNOWN_ISSUES.md`](pcie_gen3/docs/KNOWN_ISSUES.md) | Current failing tests, checker gaps / "fake passes", unimplemented spec features |

---

## 7. Understanding the result

### How PASS / FAIL is decided

The tests themselves contain **no checks** — they only drive sequences and wait. All checking is
done by the always-on passive scoreboards. `run_all.do` decides a test's result by scanning its
transcript:

```
PASS   only if   the log contains "UVM Report Summary"   (i.e. the test actually finished)
         and      no  UVM_FATAL : <non-zero>
         and      no  UVM_ERROR : <non-zero>
         and      no  "TEST FAILED" / "** Error" / "Fatal:"
FAIL   otherwise
```

Negative tests (error injection) use `Error_Report_Catcher`: the test `arm()`s the exact report ID
it expects, that armed `uvm_error` is **demoted to `UVM_INFO`** (re-tagged `EXPECTED_<id>`) and
counted, so an expected error does **not** fail the run. Anything **not** armed still fails.

> ⚠️ A test that runs, drives nothing useful and produces no error is scored **PASS**. There is no
> minimum-activity / scoreboard-drained check. See `docs/KNOWN_ISSUES.md`.

### Where to look

| What | Where |
|---|---|
| Per-test full transcript | `pcie_gen3/sim/sim/<test>/<test>.log` |
| Regression pass/fail list | `pcie_gen3/sim/sim/regression_summary.log` |
| End-of-test scoreboard summaries | search a `<test>.log` for `SUMMARY` — `Scoreboard_Top`, `DL_Scoreboard`, `FC_Manager` each print counts, undrained queues and outstanding reads at end of run |
| One packet's whole journey | every layer logs `uid=<n>` for a TLP — `grep "uid=42"` a transcript |
| A failing DW-compare | search for `DIFF` — the scoreboard prints the full aligned TX-vs-RX DW list with `*` on the differing rows |
| Coverage | `pcie_gen3/sim/coverage_reports/*.ucdb`; merged: `merged_cov.ucdb` (`vcover report -html merged_cov.ucdb`) |

---

## 8. Debugging

Full guide in [`pcie_gen3/docs/DEBUG_GUIDE.md`](pcie_gen3/docs/DEBUG_GUIDE.md). In short:

* **Normal run** (`UVM_VERBOSITY=UVM_LOW`) already prints one decoded line per TLP at each layer
  boundary, e.g.
  `TL_MON_EP  EP RX request captured -> [uid=72] MWr 4DW len=1024 addr=0x20000020 tag=0 td=1 ...`
* **`+PCIE_DEBUG`** — add this plusarg to raise the whole environment to `UVM_HIGH` (per-DW dumps,
  per-byte striping/scrambling, internal buffer/pointer state):
  ```
  vsim -c work.PCIe_top +UVM_TESTNAME=<test> +PCIE_DEBUG -l dbg.log -do "run -all; quit -f"
  ```
* **Message-ID prefixes** are consistent — grep by layer:
  `TL_MON_RC` `TL_MON_EP` `DLL_MON_RC` `DLL_MON_EP` `DLL_DRV_RC` `DLL_DRV_EP`
  `SCB_TOP` `SCB_DL` `SCB_MAC` `FC` `VC_ARB` `TX_LTSSM` `RX_LTSSM` `ENUM`
* **Verbosity tiers**: `UVM_NONE` results · `UVM_LOW` milestones + per-TLP line · `UVM_MEDIUM`
  per-layer handoff, FC credits, Ack/Nak · `UVM_HIGH` per-DW / per-byte · use `-UVM_VERBOSITY`.

---

## 9. Adding a new test

1. Add a sequence to `pcie_gen3/sequences/Sequence.sv` if you need new stimulus.
2. Add a `class <name> extends pcie_base_test` to `pcie_gen3/tests/Test.sv`
   (or `Error_Tests.sv` for a negative test). `super.run_phase(phase)` gives you link-up +
   full enumeration; then `raise_objection`, `start` your sequence, wait, `drop_objection`.
3. Add the test name to the `tests { }` list in `pcie_gen3/sim/run_all.do` (and `regr.do`).
4. Run it: `vsim -c -do "set only <name>; do run_all.do"`.

---

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `vlog failed ... Undefined variable: 'ADDR_WIDTH'` when compiling from a sub-directory | `Package.sv` has a **working-directory-relative** `` `include "../top/apb_defines.svh" ``. Compile **from `pcie_gen3/sim/`** (as all the `.do` scripts do). |
| `(vdel-134) Unable to remove locked optimized design "_opt" ... Locker is <user>@<host>` | A previous `vsim` still holds the library lock. Kill stray `vsim.exe` / `vsimk.exe`, or `rm -rf work` before re-running. Harmless if compile then reports `Errors: 0`. |
| `vsim.exe: command not found` (Linux) | Edit the `exec vsim.exe` lines in `run_all.do` / `regr.do` to `exec vsim`. |
| Test "hangs" forever | It will be scored **FAIL (did not finish)** by `run_all.do` because the transcript never reaches `UVM Report Summary`. Open the `<test>.log` and look at the last activity; common cause is a monitor waiting on a handshake that never comes. |
| Compile warnings (`Redundant digits`, `Unterminated string literal ... MAC_SB.sv`, `non-LRM randomize`, `foreach ... non-standard`, `os_s has no return value`) | Pre-existing, cosmetic, **not errors**. Compile is clean if the last line is `Errors: 0`. |

---

## 11. Current status (informational)

Last recorded regression (`regr_cov1`, Gen1): **24 / 30 PASS**. Failing tests and the reasons —
plus the checker gaps that let some passing tests pass without really verifying anything, and the
list of PCIe 3.0 features that are not implemented — are documented in
[`pcie_gen3/docs/KNOWN_ISSUES.md`](pcie_gen3/docs/KNOWN_ISSUES.md). **Read that file before you
trust a green result.**
