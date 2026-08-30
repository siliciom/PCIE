# Debug Guide

## 1. Verbosity levels

Pass `-UVM_VERBOSITY` / `+UVM_VERBOSITY=<level>` to `vsim`.

| Level | What you get |
|---|---|
| `UVM_NONE` | test result, end-of-run scoreboard `SUMMARY` blocks, fatal-class messages |
| `UVM_LOW` (default) | the above **+ one decoded line per TLP at each layer boundary**, LTSSM state transitions, enumeration steps, scoreboard MATCH / MISMATCH |
| `UVM_MEDIUM` | the above **+ per-layer packet handoff, FC credit consume/return, Ack/Nak, replay-buffer add/delete, DLL seq/LCRC assignment** |
| `UVM_HIGH` | the above **+ per-DW dumps, per-byte striping / scrambling, ordered-set bytes, internal pointers / buffer contents** |

### The `+PCIE_DEBUG` switch

```
vsim -c work.PCIe_top +UVM_TESTNAME=<test> +PCIE_DEBUG -l dbg.log -do "run -all; quit -f"
```

`pcie_base_test::start_of_simulation_phase` sees the plusarg and calls
`uvm_top.set_report_verbosity_level_hier(UVM_HIGH)` on the whole component tree. Equivalent to
`+UVM_VERBOSITY=UVM_HIGH` but survives any per-component overrides. Use it when a normal run does
not tell you enough. **Warning:** on a max-payload test this produces a very large transcript
(1024 per-DW lines per direction).

---

## 2. Message-ID map

Every log line is `UVM_INFO/ERROR <file>(<line>) @ <time>: <path> [<ID>] <text>`. Grep by `[<ID>]`:

| ID | Source | Meaning |
|---|---|---|
| `TL_MON_RC` | RC TL monitor | RC captured an **outgoing** request/completion on the wire |
| `TL_MON_EP` | EP TL monitor | EP captured an **incoming** request; ECRC check result; forwarded to LUT |
| `RX_TL_MONITOR` | EP TL monitor | malformed / ECRC / poison **errors** (packet dropped) |
| `TX_TL_MONITOR` | RC TL monitor | UR / CA completion received back on the RC |
| `MALFORMED_TLP` | EP TL monitor | length / fmt+type / byte-enable violation |
| `DLL_DRV_RC` / `DLL_DRV_EP` | DLL driver | TLP framing (seq, LCRC), replay-buffer add/delete, DLL→TL push |
| `DLL_MON_RC` / `DLL_MON_EP` | DLL monitor | DLP collected off the PCS interface: DW count, seq, LCRC |
| `RX_DLL_MON` / `TX_DLL_MON` | DLL monitor | LCRC / DLLP-CRC / sequence-number **errors** |
| `SEQ_CHECK` | DLL monitor | out-of-order / skipped DL sequence number |
| `REPLAY` | DLL driver | replay-count exceeded the limit |
| `FC` | `FC_Manager` | credit consume / return, per-VC availability, end-of-run summary |
| `VC_ARB` | `VC_Arbiter` | arbitration winner + starvation counters |
| `TX_LTSSM` / `RX_LTSSM` | MAC driver | LTSSM state transitions, rate negotiation, speed change |
| `MAC_TX_DRV` / `MAC_RX_DRV` | MAC driver | STP framing, byte striping / un-striping |
| `PMA_TX_MON` / `PMA_RX_MON` | PMA monitor | serial word capture / reassembly |
| `ENUM` | `pcie_base_test` | enumeration steps (VID, header type, BAR sizing, Command reg) |
| `LUT_REQ` | `RX_PCIe_LUT` | request received for decode |
| `MEM_MODEL` / `MEM_MODEL_DEBUG` | `Scoreboard_Top` | memory write applied, read registered, read data compared |
| `SCB_TOP` | `Scoreboard_Top` | TLP transport MATCH/MISMATCH (+ full DIFF dump), memory read result, end-of-run summary |
| `SCB_DL` | `DL_Scoreboard` | DLP / DLLP MATCH/MISMATCH (+ DIFF dump), end-of-run summary |
| `SCB_MAC` | `MAC_SB` | PHY-word MATCH/MISMATCH, first-bad-word index, end-of-run summary |
| `TEST_RESULT` | error tests | `PASS: ...` / `FAIL: ...` verdict from a negative test |
| `EXPECTED_<id>` | `Error_Report_Catcher` | an armed error that was demoted to info (the negative test expected it) |

---

## 3. Tracing one packet end-to-end (`pkt_uid`)

Every `Sequence_item` gets a unique `pkt_uid` the first time it is packed (`pack_tlp` →
`stamp_uid`). Every layer that logs the packet prints `uid=<n>` and the one-line decode via
`Sequence_item::convert2string()`, e.g.:

```
[TL_MON_RC]  RC TL TX request captured  ->  [uid=72] MWr 4DW len=1024 addr=0x20000020 tag=0 tc=0 vc=VC0 td=1 ep=0 attr=000 at=10 fBE=c lBE=3  pyld[1024]={...}  ecrc=2c322372  | 1029 DW on wire
```

So to follow packet 72:

```
grep "uid=72" pcie_gen3/sim/sim/<test>/<test>.log
```

**Caveat:** the uid follows a packet only while it is the *same object*. Monitor-side items are
rebuilt from the wire and get their **own** uid (or `uid=0` if never packed). Cross-side
correlation (RC-TX vs EP-RX) is by `tag` / `addr` / `seq`, and the scoreboard pairs them FIFO.

### `convert2string()` field key

```
[uid=N] <Type> <3DW|4DW> len=<DW>  addr=0x...  tag=<h> tc=<n> vc=VC<n> td=<b> ep=<b> attr=<attr1><attr2> at=<2b> fBE=<h> lBE=<h>  pyld[<n>]={first..last}  ecrc=<h>
```

For completions:

```
[uid=N] <Cpl|CplD> <3DW|4DW>  tag=<h>  bc=<byte-count>  loAddr=0x<lower-addr>  len=<DW>  <SC|UR|CRS|CA>  cplID=<h> reqID=<h>
```

`len` is decoded — a Length field of `0` prints as `1024` (PCIe 3.0 §2.2.7). `bc=0` in the raw
field prints as `4096` (same encoding rule).

---

## 4. Reading a scoreboard mismatch

On any DW mismatch the scoreboard prints the **full aligned TX-vs-RX list** with `*` marking the
differing rows:

```
[SCB_TOP] REQUEST TLP DATA MISMATCH (fail cnt=1)
==== REQUEST DIFF  TX[uid=72 MWr] (1029 DW)  vs  RX[uid=0 MRd] (5 DW) ====
  * DW[0]  TX=60058800  RX=2000a800
  * DW[1]  TX=0008003c  RX=000817ef
    DW[2]  TX=00000000  RX=00000000
    DW[3]  TX=20000020  RX=20000020
  * DW[4]  TX=2c322372  RX=--------
```

Read it as:

* **`TX[uid=72 MWr]` vs `RX[uid=0 MRd]`** — the scoreboard paired a write against a read. That
  means an earlier packet was **dropped** on one side, so the FIFO pairing is off by one. Look
  *up* the log for the last `PACKET DROPPED` / `ECRC MISMATCH` / size mismatch.
* **`RX=--------`** — RX has fewer DWs than TX (truncated / dropped payload).
* DW[0] carries fmt/type/length; the RC-TL and EP-TL monitors both decode it in their
  `TL_MON_*` lines — compare those to see which field diverged.

The `ECRC MISMATCH` error is self-describing:

```
[RX_TL_MONITOR] ECRC MISMATCH - PACKET DROPPED  ->  [uid=0] MWr 4DW len=1024 ...
   rcvd_ecrc=2c322372  calc_ecrc=7eb2eebb  captured_payload=0 DW (hdr Length=0 decoded=1024)
```

`captured_payload=0 DW` while `decoded=1024` immediately tells you the monitor did not capture the
payload it should have.

---

## 5. End-of-run summaries

At `UVM_NONE`, so always present. Search a transcript for `SUMMARY`:

```
================ Scoreboard_Top SUMMARY ================
  TLP transport compare : pass=46  fail=1
  Memory read compare   : pass=0   fail=0
  mem model entries     : 0 DW written
  UNDRAINED queues      : tx_req=0 rx_req=0 tx_cpl=0 rx_cpl=0
  OUTSTANDING reads     : 1
     key=000817 addr=0000000020000020 length=0 received_dw=0
```

* **`Memory read compare : pass=0`** on a Wr/Rd test → the read data was never verified.
* **`mem model entries : 0`** on a Wr test → the write never reached the memory model.
* **`OUTSTANDING reads : > 0`** → a read was issued but its completion never arrived (or never
  matched) — the `key`/`addr`/`length` tell you which.
* **`UNDRAINED queues : > 0`** → the scoreboard still holds unpaired items at end of test.

`DL_Scoreboard` and `FC_Manager` print similar blocks (DLP/DLLP pass-fail, credits remaining per
VC).

---

## 6. Waveforms

```
vsim -do run.do           # compiles, loads one test, add log -r /*, run -all
```

Then open a `.wlf` / use the GUI wave window. Key signals: `*_TL_DL_Interface.tl_tx_*`,
`*_DLL_PCS_Interface.dl_*`, `*pipe*.TxData/RxData`, `*phy*.TX/RX`, and the `Rate` pin for the
current generation.
