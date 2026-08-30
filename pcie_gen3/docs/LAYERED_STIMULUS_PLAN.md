# Plan: start stimulus from any layer (TL / DLL / MAC / PMA)

Goal: be able to run a test that injects traffic **directly at the DLL, MAC or PMA layer**
(bypassing the layers above it), on either the RC or the EP side, **without changing any of the
existing interface / TLM connections or the existing test flow.**

Status: **Phase 1 (analysis) + Phase 2 (infra) done; DLL injection path verified.**
- `STIM_TL` (default) path re-verified unchanged: `Single_Mem_Wr_Rd_3DW_test` still passes 0/0.
- `layer_dll_memwr_smoke_test`: a bare MEM_WR injected at `PCIe_DLL_Seqr` arrives byte-identical at
  the EP TL monitor; `DL_Scoreboard` DLP compare pass=47/0 (the injected TLP is the last entry,
  10 DW = seq + 8 + LCRC that the DLL driver added); 0 errors / 0 fatals.
MAC + PMA smoke tests are next. See §5 for phases, §7 for the change log.

---

## 1. How the TB feeds each layer today (findings)

Every layer driver follows the **same pattern**:

```
  interface(N-1 <-> N)  ──snoop──▶  Monitor(N)  ──write_*()──▶  <internal queue / mailbox>  ──▶  Driver(N) processing  ──drive──▶  interface(N <-> N+1)
```

The **Monitor of layer N reconstructs what the layer above put on the wire and hands it to the
Driver of layer N** through an analysis-imp `write_*()` function. The layers are already fully
decoupled through the SystemVerilog interfaces + this monitor snoop.

Every agent also does `drv.seq_item_port.connect(seqr.seq_item_export)` in `connect_phase` — so
**all four layer drivers are already connected to a sequencer.** For the TL that connection is
used; for DLL / MAC / PMA the sequencer is currently **dead weight** (the driver's `run_phase`
never calls `get_next_item`).

### Exact injection point per layer (RC / TX direction)

| Layer | Sequencer (already exists) | How the driver gets data today | The single internal hand-off point to feed | What the payload must be |
|---|---|---|---|---|
| **TL** | `RC_Env[i].PCIe_TL_Agnt.TX_TL_Seqr` | `PCIe_TL_Driver::rc_feeder()` → `seq_item_port.get_next_item(req)` → `req.pack_tlp()` → `vc_arb.push(req)` | *(already sequencer-driven — nothing to add)* | a `Sequence_item` with TLP fields (fmt, type, addr, length, payload, tag, tc, td …) |
| **DLL** | `RC_Env[i].PCIe_DLL_Agnt.PCIe_DLL_Seqr` | `PCIe_DLL_Monitor.rc_TX_MD_ap` → `PCIe_DLL_Driver::write_TX(t_x)` → `rc_tx_pkt_mb.try_put(t_x)`; consumed in the `DL_ACTIVE` state as `tx_pkt.tx_data_t` → `rc_tx_recived_packet(dw_q)` (adds seq #, LCRC, replay-buffer entry) | **`rc_tx_pkt_mb.put(req)`** where `req.tx_data_t` = the raw TLP DW list | a `Sequence_item` whose **`tx_data_t`** queue holds a bare TLP: header DWs + payload (+ ECRC if TD). **No sequence number, no LCRC** — the DLL driver adds those. |
| **MAC** | `RC_Env[i].TX_MAC_Agnt.seqr` | `PCIe_MAC_monitor.mac_tx_dll_port` → `PCIe_MAC_driver::write_port_e(t)` → per-TLP `rc_add_stp_to_all_packets()` → flattened into `rc_received[$]`; consumed by the LTSSM `L0` state (byte-stripe, scramble, drive PIPE) | **`write_port_e(req)`** where `req.mac_tx_data` is a queue-of-queues | a `Sequence_item` whose **`mac_tx_data[i]`** holds each **fully framed DLL packet** (sequence# + header + payload + ECRC + LCRC). The MAC driver adds the STP token and stripes. |
| **PMA** | `RC_Env[i].TX_PMA_Agnt.PCIe_PMA_seqr` | `PCIe_PMA_monitor.pma_tx_mac_port` → `PCIe_PMA_driver::write_port_c(pma_rx)` → `mac_tx_data_q[lane]`; serialised bit-by-bit onto `phy_tx_vif.TX[lane]` | **`write_port_c(req)`** where `req.pma_tx_data[lane]` is filled | a `Sequence_item` whose **`pma_tx_data[lane][$]`** holds the per-lane **130-bit blocks** (2'b10/2'b01 sync header + 128 scrambled bits) ready to serialise. |

EP / RX direction is the mirror image (`ep_tx_pkt_mb`, `write_tx` lower-case, `write_port_g/h`,
`write_port_a/b`; sequencers `EP_Env[i].*`).

### Link bring-up

* Training runs **autonomously** from `RESET` deassert — the MAC drivers on both sides drive the
  LTSSM; no sequence is involved.
* `PCIe_DLL_Driver` advances `DL_INACTIVE → DL_INIT_FC1 → DL_INIT_FC2 → DL_ACTIVE` once
  `rc_link_up` is set by L0, and triggers the global events `DL_active_env` (RC) /
  `DL_active_env_rx` (EP).
* `pcie_base_test::run_phase` blocks on **both** of those, then runs `do_enumeration()`. Every
  functional test calls `super.run_phase()` first, so it only starts after link-up + enumeration.
* **The DLL driver's TX inject path only runs inside `DL_ACTIVE`.** MAC/PMA inject can run during
  training but will contend with the LTSSM's own ordered-set traffic on the same interface.

### Scoreboards — good news

`DL_Scoreboard` compares the **RC-side DLL monitor capture** vs the **EP-side DLL monitor
capture**; `MAC_SB` compares RC vs EP **PHY words**; `Scoreboard_Top` compares RC-TX TLP vs EP-RX
TLP. All of these snoop the **wire**, not the layer above. So **if you inject at the DLL layer,
`DL_Scoreboard` still verifies that what you injected was transported to the EP unchanged** — the
existing scoreboards remain valid for layer tests. Layer tests only need **additional** targeted
checks (see §4).

---

## 2. Design — what to add (no connection changes)

### 2.1 Config knob (`env/env_config.sv`)

```systemverilog
typedef enum { STIM_TL, STIM_DLL, STIM_MAC, STIM_PMA } stim_layer_e;
stim_layer_e stim_layer = STIM_TL;   // default = today's behaviour
```

* `STIM_TL` (default) → unchanged: tests drive `TX_TL_Seqr`, everything flows down.
* `STIM_DLL` / `STIM_MAC` / `STIM_PMA` → that layer's driver takes its input from its **own
  sequencer** instead of the monitor snoop.

Set by the test in `build_phase` on each `rc_cfg[i]` / `ep_cfg[i]` **before** the envs are built.

### 2.2 One `run_phase` branch per driver (DLL, MAC, PMA)

Add to each driver's `run_phase` (RC and EP variants), gated by `cfg.stim_layer`:

```systemverilog
// PCIe_DLL_Driver (RC side)
if (cfg.stim_layer == STIM_DLL) begin
  fork
    forever begin
      Sequence_item req;
      seq_item_port.get_next_item(req);
      wait (rc_dl_state == DL_ACTIVE);      // DLL TX path is only live here
      rc_tx_pkt_mb.put(req);                // SAME mailbox write_TX() uses
      seq_item_port.item_done();
    end
  join_none
end
```

```systemverilog
// PCIe_MAC_driver (RC side)
if (cfg.stim_layer == STIM_MAC) begin
  fork forever begin
    Sequence_item req;
    seq_item_port.get_next_item(req);
    write_port_e(req);                      // SAME function the monitor feed calls
    seq_item_port.item_done();
  end join_none
end
```

```systemverilog
// PCIe_PMA_driver (RC side)
if (cfg.stim_layer == STIM_PMA) begin
  fork forever begin
    Sequence_item req;
    seq_item_port.get_next_item(req);
    write_port_c(req);                      // SAME function the monitor feed calls
    seq_item_port.item_done();
  end join_none
end
```

The monitor→driver `write_*()` connection **stays** — it just carries no traffic because no
higher-layer sequence runs when `stim_layer != STIM_TL`. Nothing is disconnected.

### 2.3 `Sequence_item` builder helpers (`sequences/Sequence_item.sv`)

Reuse the existing `Sequence_item` (it already has `tx_data_t`, `mac_tx_data`, `pma_tx_data`…).
Add helpers that populate the field the target layer consumes:

| Helper | Fills | Uses |
|---|---|---|
| `build_dll_stream()` | `tx_data_t` ← `pack_tlp(); tlp_q` (bare TLP, no seq/LCRC) | DLL injection |
| `build_dllp(kind, seq)` | `dllp_tx_packet` / the Ack-Nak / FC DLLP DW pair | DLL DLLP injection |
| `build_mac_stream(seq_no)` | `mac_tx_data[0]` ← `{seq_no, pack_tlp().tlp_q, lcrc}` (framed DLL packet) | MAC injection |
| `build_mac_os(ts1/ts2/skp/eios …)` | `os_t_lane[lane]` ← ordered-set bytes | MAC LTSSM injection |
| `build_pma_blocks(lane)` | `pma_tx_data[lane]` ← 130-bit scrambled blocks from a DW stream | PMA injection |

(LCRC / scramble helpers already exist in `PCIe_DLL_Driver` / `PCIe_MAC_Driver`; factor the pure
functions into a shared `pcie_pkg` utility file so the sequences can call them.)

### 2.4 Layer base sequences (`sequences/`)

New file `sequences/Layer_Sequences.sv`, three classes:

```systemverilog
class pcie_dll_base_seq extends uvm_sequence #(Sequence_item);
  // API:  send_tlp(Sequence_item tlp)        - inject a bare TLP, DLL adds seq+LCRC
  //       send_raw(bit [31:0] dw_q[$])       - inject arbitrary DW list
  //       send_dllp(ack_nak_e kind, seq)     - inject a DLLP
endclass

class pcie_mac_base_seq extends uvm_sequence #(Sequence_item);
  // API:  send_framed(Sequence_item tlp, seq_no)   - inject a DLL-framed packet
  //       send_os(os_kind_e kind)                  - inject TS1/TS2/SKP/EIOS
endclass

class pcie_pma_base_seq extends uvm_sequence #(Sequence_item);
  // API:  send_blocks(bit [129:0] blk_q[$][NUM_LANES])
  //       send_dw_stream(bit [31:0] dw_q[$])       - helper scrambles+blocks it
endclass
```

### 2.5 Layer base test (`tests/`)

New `tests/Layer_Tests.sv`:

```systemverilog
class layer_base_test extends pcie_base_test;
  rand stim_layer_e stim_layer;
  bit  wait_link_up = 1;      // DLL tests: keep 1.  MAC/PMA-training tests: set 0.
  bit  do_enum      = 0;
  bit  inject_on_ep = 0;      // 0 = inject on RC (toward EP), 1 = inject on EP (toward RC)

  function void build_phase(uvm_phase phase);
    // set stim_layer on every rc_cfg / ep_cfg BEFORE super.build_phase creates the envs
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    if (wait_link_up) begin DL_up_env_rx.wait_ptrigger(); DL_up_env.wait_ptrigger(); end
    if (do_enum)      do_enumeration();
    // derived test starts its pcie_<layer>_base_seq on the right sequencer:
    //   RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Seqr   /  .TX_MAC_Agnt.seqr  /  .TX_PMA_Agnt.PCIe_PMA_seqr
    phase.drop_objection(this);
  endtask
endclass
```

(It **cannot** just call `super.run_phase()` because that always waits for link-up + enumerates;
hence the re-implemented body with knobs.)

---

## 3. Requirements checklist

| # | Requirement | Where it is handled |
|---|---|---|
| R1 | No change to existing TLM / interface connections | monitor→driver and seqr→driver connections are untouched; only `run_phase` logic is added |
| R2 | No change to existing test behaviour | new branch is gated by `cfg.stim_layer`, default `STIM_TL` |
| R3 | Inject at DLL / MAC / PMA | §2.2 — one `run_phase` fork per driver feeding the existing internal hand-off |
| R4 | Inject on RC **or** EP side | start the sequence on that side's agent sequencer; drivers get RC/EP branch by `cfg.mode` (already there) |
| R5 | Layer-appropriate stimulus abstraction | §2.3 builder helpers + §2.4 layer sequences |
| R6 | Some layer tests must run before/without link-up + enumeration | §2.5 `layer_base_test` with `wait_link_up` / `do_enum` knobs |
| R7 | Existing scoreboards keep working | they snoop the wire, not the layer above (§1) |
| R8 | Targeted per-layer checks | §4 |
| R9 | Trace an injected packet | `pack_tlp()` stamps `pkt_uid`; the debug traces from the `fa2e063` commit already print `uid=` at every layer |

### Open questions / risks

* **DLL inject needs `DL_ACTIVE`.** Injecting a DLLP *during* FC-init needs an extra hook earlier
  in the DLL FSM. Out of scope for v1 (v1 = inject in `DL_ACTIVE`).
* **MAC/PMA inject during LTSSM training** contends with the LTSSM's own ordered-set driving on
  the same PIPE/PHY interface. v1 should inject only when the LTSSM is in a state that isn't
  actively driving (e.g. `L0`, or a directed "quiet" window). A true "drive raw ordered sets
  during Polling" test needs the MAC driver to yield the interface to the sequence — a bigger
  change, v2.
* **`Sequence_item` static fields** (`count_tlp`, `size_tx_rx`, …) are shared across all items —
  an injected item that touches them could perturb the monitor-side bookkeeping. Audit before
  Phase 2.
* **Back-pressure / handshake**: the injected `put()` into `rc_tx_pkt_mb` is unbounded; a fast
  sequence could outrun the DLL driver. Use a bounded mailbox or a done-event per item.
* Reusing `Sequence_item` for four very different abstractions keeps the type system simple but
  makes a sequence able to set fields the target layer ignores. Acceptable for v1; consider three
  typed subclasses later.

---

## 4. Checkers for layer tests (Phase 4)

The wire-level scoreboards (`DL_Scoreboard`, `MAC_SB`, `Scoreboard_Top`) already verify
"what I injected reached the EP unchanged". Add a small **`Layer_Scoreboard`** (or extend the
existing ones with a second "golden reference" input) that checks what the **layer under test
added**:

| Injecting at | Check that the layer added / did |
|---|---|
| **DLL** | correct sequence number (== `rc_next_transmit_seq`), correct LCRC (golden recompute over seq+TLP), replay-buffer entry created, Ack consumed / retransmit on Nak |
| **MAC** | correct STP token (length field = DW count, framing CRC), byte-striping across `num_lanes` is reversible, scrambler advanced correctly |
| **PMA** | 130-bit block sync headers (2'b10 data / 2'b01 OS), per-lane scrambler LFSR, bit-exact serialisation, SKP handling |

---

## 5. Phased plan

| Phase | Work | Deliverable |
|---|---|---|
| **1** | this analysis + design | this document |
| **2** | infra: `stim_layer_e` in `env_cfg`; 3 driver `run_phase` branches (RC+EP); `Sequence_item` builder helpers; shared LCRC/scramble util file; `Layer_Sequences.sv`; `layer_base_test` | compiles; `STIM_TL` path byte-for-byte unchanged (re-run the full regression to confirm) |
| **3** | infra smoke test: inject the **same** TLP at TL, then DLL, then MAC — assert the EP receives an identical TLP each time (`Scoreboard_Top` / `DL_Scoreboard` pass); one PMA smoke test | 3–4 smoke tests green |
| **4** | real layer tests + `Layer_Scoreboard` targeted checks; add them to `run_all.do` | new test suite + doc update |

## 6. Files that will change / be added (Phase 2)

| File | Change |
|---|---|
| `env/env_config.sv` | + `stim_layer_e` enum + field |
| `agents/PCIe_DLL_Driver.sv` | + `STIM_DLL` fork in `rc_run_phase_body` / `ep_run_phase_body` |
| `agents/PCIe_MAC_Driver.sv` | + `STIM_MAC` fork in `run_phase` RC/EP branches |
| `agents/PCIe_PMA_Driver.sv` | + `STIM_PMA` fork in `run_phase` RC/EP branches |
| `sequences/Sequence_item.sv` | + `build_dll_stream()` / `build_mac_stream()` / `build_pma_blocks()` helpers |
| `sequences/pcie_util_pkg.sv` *(new)* | pure LCRC / CRC-16 / scramble functions, shared by driver + sequence |
| `sequences/Layer_Sequences.sv` *(new)* | `pcie_dll_base_seq` / `pcie_mac_base_seq` / `pcie_pma_base_seq` |
| `tests/Layer_Tests.sv` *(new)* | `layer_base_test` + first smoke tests |
| `top/Package.sv` | `` `include `` the two new files |
| `docs/ARCHITECTURE.md` | add the "layered stimulus" section |
| `sim/run_all.do` | add the new tests to the list |

**No file that defines a TLM connection (`*_Agent.sv`, `Env_Top.sv`, `TOP.sv`) changes.**

---

## 7. Phase-2 change log (done)

| File | What was added |
|---|---|
| `env/env_config.sv` | `typedef enum { STIM_TL, STIM_DLL, STIM_MAC, STIM_PMA } stim_layer_e;` and `stim_layer_e stim_layer = STIM_TL;` |
| `sequences/Sequence_item.sv` | `calculate_lcrc(dw_q)`; `build_dll_stream()` (fills `tx_data` + `tx_data_t`); `build_mac_stream(seq_no)` (fills `mac_tx_data` + `mac_rx_data` with `{seq, tlp_q, lcrc}`); `build_pma_blocks(dw_q, lane)` (2'b10 sync header + 4 DW, **not scrambled**) |
| `agents/PCIe_DLL_Driver.sv` | `dll_stim_seqr_thread()` — forked in `run_phase` RC & EP branches when `cfg.stim_layer == STIM_DLL`; waits for `DL_ACTIVE` / `EP_DL_ACTIVE`, then `put`s the item into `rc_tx_pkt_mb` / `ep_tx_pkt_mb` (the same mailbox `write_TX`/`write_tx` feed) |
| `agents/PCIe_MAC_Driver.sv` | `mac_stim_seqr_thread()` — `fork ... join_none` at the top of `run_phase` when `STIM_MAC`; RC → `write_port_e(req)`, EP → `write_port_g(req)` |
| `agents/PCIe_PMA_Driver.sv` | `pma_stim_seqr_thread()` — `fork ... join_none` when `STIM_PMA`; RC → `write_port_c(req)` (EP side is a v2 item, warns) |
| `sequences/Layer_Sequences.sv` *(new)* | `pcie_dll_base_seq` (`send_tlp` / `send_raw`), `pcie_mac_base_seq` (`send_framed`), `pcie_pma_base_seq` (`send_dw_stream`) |
| `tests/Layer_Tests.sv` *(new)* | `layer_base_test` (knobs `stim_layer` / `wait_link_up` / `do_enum` / `inject_on_ep`; sets `stim_layer` on `rc_cfg`/`ep_cfg` in `build_phase` after `super`; re-implements `run_phase`; `dll_seqr()` / `mac_seqr()` / `pma_seqr()` accessors; `virtual task body()`) + `layer_dll_memwr_smoke_test`, `layer_mac_memwr_smoke_test` |
| `top/Package.sv` | `include` `Layer_Sequences.sv` (after `Sequence.sv`) and `Layer_Tests.sv` (after `Error_Tests.sv`) |

### How to use it (once smoke-verified)

```systemverilog
class my_dll_test extends layer_base_test;
  function new(...); super.new(...);
    stim_layer = STIM_DLL;  wait_link_up = 1;  do_enum = 1;  inject_on_ep = 0;
  endfunction
  task body(uvm_phase phase);
    pcie_dll_base_seq s = pcie_dll_base_seq::type_id::create("s");
    Sequence_item     t = Sequence_item::type_id::create("t");
    assert(t.randomize() with { e_type==MEM_WR; e_fmt==FMT_3DW_DATA; length==4; td==1;
                                addr == bar_base[0]+64'h40; payload.size()==4; });
    s.send_tlp(t);                    // DLL driver adds seq # + LCRC
    #200000;
  endtask
endclass
```

Run: `vsim -c -do "set only my_dll_test; do run_all.do"` (after adding it to the list), or a
direct `+UVM_TESTNAME=my_dll_test`.
