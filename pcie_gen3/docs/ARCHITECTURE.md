# Environment Architecture

## 1. Big picture

There is **no RTL DUT**. `PCIe_top` (`top/TOP.sv`) builds two complete UVM environments —
one **Root Complex (RC)** and one **Endpoint (EP)** — and connects them PHY-to-PHY:

```
      RC_Env_0  (env_cfg.mode = RC_MODE)          EP_Env_0  (env_cfg.mode = EP_MODE)
   ┌───────────────────────────────┐           ┌───────────────────────────────┐
   │  TL  agent  (driver+monitor)  │           │  TL  agent  (monitor + LUT)   │
   │  DLL agent  (driver+monitor)  │           │  DLL agent  (driver+monitor)  │
   │  MAC agent  (driver = LTSSM)  │           │  MAC agent  (driver = LTSSM)  │
   │  PMA agent  (serialiser)      │           │  PMA agent  (serialiser)      │
   └──────────────┬────────────────┘           └───────────────┬───────────────┘
                  │ RC_PHY_TX.TX[l]  ───────────────────────▶  EP_PHY_RX.RX[l]
                  │ RC_PHY_TX.RX[l]  ◀───────────────────────  EP_PHY_RX.TX[l]
                  └───────────── serial per-lane loopback (TOP.sv generate block) ────┘

   Scoreboards (test-level, one set, fed by both envs' monitors):
       Scoreboard_Top   TL_Scoreboard   DL_Scoreboard   MAC_SB (PCIe_MAC_Scoreboard)
```

The sequencer in each test drives `RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr`. The RC turns that into a
TLP, pushes it down its own layer stack, across the loopback wires, and up the EP stack; the EP's
`RX_PCIe_LUT` decodes it and generates the completion, which travels back the same way.

## 2. The layer stack (per env)

Each `Env_Top` builds one stack. Every agent has a `RC_MODE` and an `EP_MODE` code path selected
by `env_cfg.mode`.

| Layer | Agent | Driver does | Monitor does | Interface |
|---|---|---|---|---|
| **TL** | `PCIe_TL_*` | RC: pack a `Sequence_item` into `tlp_q` (header DW0..3, payload, ECRC), gate on FC credit (`VC_Arbiter` + `FC_Manager`), drive DW-by-DW on `TX_TL_DL`. EP: drive completion DWs on `RX_TL_DL`. | Capture the TLP DW stream, decode the header, run **malformed-TLP checks** (length, IO/CFG length, fmt+type, byte enables, poison), ECRC check on RX, publish to scoreboards / to `RX_PCIe_LUT`. | `TX_TL_DL_Interface`, `RX_TL_DL_Interface` |
| **DLL** | `PCIe_DLL_*` | Frame the TLP: prepend a 12-bit **sequence number**, append **LCRC**, store in a **2048-entry replay buffer**. Handle **Ack/Nak** (delete acked entries, replay on Nak / on **replay-timer** expiry), send **InitFC1/2 / UpdateFC** DLLPs. `DL_INACTIVE → DL_INIT_FC1 → DL_INIT_FC2 → DL_ACTIVE`. | Collect the framed DLP off the PCS interface, check **LCRC** and **sequence number** (gap → Nak, stale → Ack+drop), check **DLLP CRC-16**, publish. | `TX_DLL_PCS_Interface`, `RX_DLL_PCS_Interface` |
| **MAC / LTSSM** | `PCIe_MAC_*` | The **LTSSM**: `Detect → Polling → Configuration → L0`, `Recovery.RcvrLock/RcvrCfg/Speed/Idle`, `Loopback.Entry/Active/Exit`, `Hot Reset`, `Disabled`. Exchanges **TS1/TS2** ordered sets (with Rate ID, Link#, Lane#), negotiates link width and generation, adds the **STP** framing token per TLP, **byte-stripes** across lanes. | Un-frame (find one STP per TLP), un-stripe, forward to DLL. Also flags out-of-order DL sequence / framing anomalies. | `pipe_tx_interface`, `pipe_rx_interface` |
| **PMA** | `PCIe_PMA_*` | Per lane: **scramble** (23-bit Gen3 LFSR), pack into **130-bit** blocks (`2'b10`/`2'b01` sync header), **serialise** bit-by-bit onto `phy_*_interface.TX[lane]`. | Deserialise the serial stream, descramble, reassemble 32-bit DWs, forward to MAC. | `phy_tx_interface`, `phy_rx_interface` |

Supporting blocks:

* **`RX_PCIe_LUT`** (EP side, in the TL agent) — decodes the request address against the EP's BARs,
  generates the completion(s): normal `CplD` (split at `MAX_CPL_BYTES = 128`), `UR` for an
  unclaimed address, `CA` for a reserved trigger offset. Also routes CfgRd/CfgWr to
  `EP_Config_Space`.
* **`EP_Config_Space`** — the EP's Type-0 configuration header + BAR sizing model.
* **`TAG_Manager`** — allocates / frees the 8-bit tags for outstanding non-posted requests.
* **`FC_Manager`** — per-VC credit pools (PH/PD/NPH/NPD/CPLH/CPLD); `consume_credit` on TX,
  `return_credit` after the LUT processes a request; drives the credit values onto the TL↔DL
  interface for the DLL to advertise.
* **`VC_Arbiter`** — 8 per-VC queues, **strict-priority** (VC7 > … > VC0); a VC is skipped only if
  empty or its head-of-line packet lacks FC credit.

## 3. Clocks (`TOP.sv`)

`timescale 1ns/100ps`.

| Clock | Toggle | Freq | Used for |
|---|---|---|---|
| `CLK` | `#2` | 250 MHz | the TL/DL/internal logic clock (`CLK` on every `*_Interface`) |
| `CLK_GEN1` | `#2` | 250 MHz | PIPE clock when running Gen1 |
| `CLK_GEN2` | `#1` | 500 MHz | PIPE clock when running Gen2 |
| `CLK_GEN3` | `#0.5` | 1 GHz | PIPE clock when running Gen3 |

`RC_PCLK[i]` / `EP_PCLK[i]` are muxed between GEN1/2/3 by the `Rate` pin, which the MAC driver
drives from `Recovery.Speed`.

## 4. Configuration knobs

Compile-time (`+define+` on `vlog`), defaults in `top/pcie_top_defines.svh`:

| Macro | Default | Meaning |
|---|---|---|
| `NUM_RC` / `NUM_EP` | 1 | number of RC / EP env instances |
| `NUM_RC_GEN` / `NUM_EP_GEN` | 1 | advertised PCIe generation (1/2/3) — copied to `env_cfg.gen` in `pcie_base_test::build_phase` |
| `NUM_LANES` | 1 | lanes per link |
| `NUM_VC` | 8 | virtual channels modelled |

Run-time (`+plusarg` on `vsim`):

| Plusarg | Effect |
|---|---|
| `+UVM_TESTNAME=<name>` | which test to run |
| `+UVM_VERBOSITY=<level>` | UVM_NONE / UVM_LOW / UVM_MEDIUM / UVM_HIGH |
| `+PCIE_DEBUG` | raise the whole env to UVM_HIGH (see DEBUG_GUIDE.md) |

`env_cfg` (`env/env_config.sv`) also carries all the LTSSM timeout values used by the LTSSM tests.

## 5. Data flow of one memory write+read (functional test)

```
test.run_phase
  └─ super.run_phase  ── pcie_base_test: wait DL_active (both sides), do_enumeration()
                          (CfgRd VID/DID, header type, read+size+assign BARs, enable Command reg)
  └─ Mem_Seq.start(RC TX_TL_Seqr)
        MEM_WR:  seq_item ─▶ TL drv: pack_tlp (stamp uid) ─▶ VC_Arbiter ─▶ FC gate
                 ─▶ DLL drv: +seq +LCRC, replay-buffer  ─▶ MAC drv: +STP, stripe
                 ─▶ PMA drv: scramble, 130b, serialise  ─▶ [loopback wire]
                 ─▶ EP PMA mon ─▶ EP MAC mon (un-STP, un-stripe)
                 ─▶ EP DLL mon (LCRC / seq check)       ─▶ EP TL mon (decode, malformed checks, ECRC)
                 ─▶ RX_PCIe_LUT: apply payload to mem_space[]
        MEM_RD:  same path down to RX_PCIe_LUT
                 ─▶ generate_mem_cpl: build CplD fragments from mem_space[]
                 ─▶ EP TL drv ─▶ EP DLL/MAC/PMA ─▶ [wire] ─▶ RC PMA/MAC/DLL mon
                 ─▶ RC TL mon (collect completion)
        Scoreboard_Top:
          - compare_tlp:  RC-TX TLP DW list  vs  EP-RX TLP DW list   (transport intact?)
          - mem model:    reassemble the CplD payload, compare vs what MEM_WR stored (data correct?)
        DL_Scoreboard:    RC-sent DLP  vs  EP-received DLP            (DLL transport intact?)
        MAC_SB:           RC-TX PHY words  vs  EP-RX PHY words        (PHY transport intact?)
```

## 6. Scoreboards

| Scoreboard | Compares | Pass counter | Fails on |
|---|---|---|---|
| `Scoreboard_Top` | (a) RC-TX TLP `tlp_q` vs EP-RX TLP `tlp_q`; (b) read-completion payload vs `mem_space[]` model | `pass_cnt` (transport), `mem_pass_cnt` (data) | size mismatch, any DW mismatch, read data mismatch, unmatched CplD, poisoned write |
| `DL_Scoreboard` | RC↔EP DLP and DLLP DW lists | `DL_pass_cnt`, `DLLP_pass_cnt` | any DW mismatch (**no size gate** — see KNOWN_ISSUES #5) |
| `MAC_SB` | RC-TX vs EP-RX 130-bit PHY words | `PL_pass_cnt` | size or any word mismatch |
| `TL_Scoreboard` | pairs a TL request with its completion, forwards the pair to `Scoreboard_Top` | — | — |

All scoreboards print an end-of-run `SUMMARY` block (counts, undrained queues, outstanding reads,
credits remaining) at `UVM_NONE` so it is always in the transcript. **None of them currently fail
the test if they simply received no traffic** — see `KNOWN_ISSUES.md`.
