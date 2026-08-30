# Known Issues & Limitations

Read this before trusting a green result. Three sections:

1. **Currently failing tests** — real bugs that make a test fail.
2. **Weak / "fake" passes** — tests that pass without actually verifying what their name implies.
3. **Unimplemented PCIe 3.0 features** — what the environment does not model at all.

---

## 1. Currently failing tests (`regr_cov1`, Gen1: 24/30)

| Test | Symptom | Root cause |
|---|---|---|
| `Single_Mem_Wr_Rd_3DW_Max_payload_test` | `ECRC MISMATCH - PACKET DROPPED` on the 1024-DW write, then `Scoreboard_Top` DW mismatch | **`#0a`** — the EP TL monitor captures payload using the **raw** Length field (`payload_dw = r_x.length`) instead of decoding `0 ⇒ 1024` (PCIe 3.0 §2.2.7). A max-payload TLP therefore captures **0** payload DW; the ECRC recompute over a header-only packet then mismatches the received ECRC. Occurs at all generations. Same class of bug in `PCIe_TL_Monitor.sv` at ~4 sites and in `RX_PCIe_LUT.sv generate_mem_cpl` (`bytes_remaining = req.length * 4` → 0, so a max-payload **read** produces **no completion** at all). |
| `B2B_Mem_Wr_Rd_3DW_test` | one spurious `LCRC MISMATCH` on the EP side | **DW-boundary mis-detection.** `ep_collect_tlp()` in `PCIe_DLL_Monitor.sv` delimits a TLP only by `!RX_DLL_PCS.dl_rx_valid`. When two TLPs are driven back-to-back with no idle cycle, the collect loop for packet N runs straight through packet N+1: `body_q` merges both, `body_q.pop_back()` returns the wrong DW as "the LCRC", and `ep_calculate_lcrc()` runs over a straddling DW list. It is a testbench monitor bug (gapless back-to-back TLPs are legal PCIe), not a DUT bug. Fix: delimit by the TLP length from the header (or by the framing marker), not by `dl_rx_valid`. |
| `Multiple_IO_Wr_Rd_3DW_test` | 32× `UNSUPPORTED_REQ completion received (UR)` on the RC side | The EP is answering IO requests with UR. Under investigation — likely IO-BAR decode or an outstanding-request count limit in `RX_PCIe_LUT`. |
| `TL_Fmt_Rtype_Illegal_test` | `TEST_RESULT FAIL: illegal fmt+r_type combination was not flagged`, plus 2 real `MALFORMED_TLP` errors | The monitor **does** flag the injected error, but with the message `"Illegal/reserved fmt+r_type combination: ..."`. The test arms the substring `"Reserved fmt encoding"`, which never appears, so `Error_Report_Catcher.hit_cnt` stays 0, `TEST_RESULT FAIL` fires, and the (unarmed) `MALFORMED_TLP` errors are not demoted. Fix the arm string or the monitor message so they agree. |
| `PHY_STP_Framing_Error_test` | `TEST_RESULT FAIL: corrupted framing marker was NOT detected`, plus a real `SEQ_CHECK` error | The dropped framing marker manifests as an **out-of-order DL sequence number** (`SEQ_CHECK`, `expected 23 got 24`), not on the `PHY_FRAMING` path the test watches. The injected error *is* detected — just on a different checker than the test arms. |
| `DLL_Replay_Timer_test` | 2000+ cascading errors (`MAC_SB`, `DL_Scoreboard`, `RX_DLL_MON` CRC) | Genuine replay-path bug: after the replay-timer retriggers a retransmission, RX sequence numbers drift (off-by-one, then growing) and both scoreboards desync catastrophically. Replayed TLPs appear to be counted as new packets. |

---

## 2. Weak / "fake" passes

The pass/fail rule (`run_all.do` / `regr.do`) is: *log exists, reached "UVM Report Summary", no
`UVM_ERROR`/`UVM_FATAL`, no "TEST FAILED"*. **No scoreboard fails the test if it simply received
no traffic** — none of `Scoreboard_Top`, `MAC_SB`, `DL_Scoreboard` check in `report_phase` that
`pass_cnt > 0`, that their queues drained, or that `pending_reads` is empty. So a silent
connectivity break, a dropped stimulus, or an un-exercised path all still show green.

| # | Test(s) | Why the pass is not meaningful |
|---|---|---|
| **#0/#1** | `Single_Mem_Wr_Rd_4DW_Max_payload_test` | Passes at Gen1 only because its 1024-DW read **produces zero completions** (see #0a above), so the memory-model check never runs (`mem_pass_cnt = 0`), and — at Gen1 — the write also never reaches the model. Nothing verifies the 4 KB payload in either direction. At Gen3 the same test **fails** (the write is caught). |
| **#2** | `LTSSM_Disabled_test`, `LTSSM_Loopback_test`, `LTSSM_HotReset_test` | No checker at all. The test sets a config bit, waits, ends. There is no env-side LTSSM scoreboard; the MAC driver only `uvm_error`s on "Receiver Detection Timeout". If the model ignored the directive entirely the test would still pass. State entry *is* logged (a human can eyeball it) but nothing asserts it. |
| **#3** | `Single_IO_Wr_Rd_3DW_test`, `B2B_IO_Wr_Rd_3DW_test` | `Scoreboard_Top` explicitly skips the data check for IO/CFG completions (`"skipping mem check"`); IO writes are never modelled. Only TLP transport (DW-equality between the two monitors) is checked. A model that returned wrong IO read data would still pass. |
| **#4** | all 8 passing `TL_*_Error_test` | Detection **is** real and time-correlates with the injection, but the pass criterion is only *"the armed error ID appeared once in a 50 µs window"*. Nothing checks recovery / correct handling — e.g. `DLL_LCRC_Error_test`'s message says "detected → NAK + replay" but it never verifies a NAK was sent or the replayed packet was accepted (`mem_pass_cnt = 0`). |
| **#5** | `DLL_Replay_Num_Rollover_test` | Arms **two** IDs (`RX_DLL_MON`/"LCRC MISMATCH" **and** `REPLAY`/"exceeded replay limit") and passes on `hit_cnt > 0` = *either*. The logs show only the LCRC-mismatch hits — the "exceeded replay limit" error the test exists to prove **never fires**. Effectively a fake pass. |

### Checker bugs

* **`DL_Scoreboard.compare_tlp1/2` have no size check** — they iterate the TX index range and read
  `rx[i]`; extra DWs on the RX side are silently ignored, so a merged / padded RX packet is
  reported as MATCH. (`Scoreboard_Top` and `MAC_SB` do check `.size()`.)
* `Error_Report_Catcher` matches on **report ID + message substring only**, process-wide, for the
  whole test window. For non-specific IDs (e.g. `RX_DLL_MON`/"LCRC MISMATCH") any spurious
  occurrence counts as the expected hit.
* `pcie_cov.sv` `cp_length` has bins for `1..1024` on `item.length`, but a 1024-DW transfer sets
  `length = 0`, which lands in **no bin** — the max-payload case is uncovered.
* Several tests pass the wrong default `name` to `new()` (copy-paste); harmless with the factory.
* `Multiple_Mem_Wr_Rd_4DW_rand_length_test` is defined in `Test.sv` but not in any regression list.

---

## 3. Unimplemented PCIe 3.0 features

Reference: *PCI Express Base Specification, Revision 3.0*.

### Transaction Layer (Ch 2)
* **Message TLPs — not implemented.** All `MSG_*` are enum'd with a print stub only: no header
  packing, no sequence, no routing, no handling. ⇒ no INTx, PM, error, vendor-defined, or hot-plug
  messages; no LN; no PTM.
* AtomicOps (FetchAdd / Swap / CAS), TPH / Steering Tags, TLP Prefixes, ATS semantics, Multicast.
* Completion Timeout mechanism.
* Attributes (RO / NS / IDO) and TC are carried but **no ordering rules are enforced**.
* Read Completion Boundary (RCB) is implicit in the memory model; `MAX_CPL_BYTES` is hard-coded at
  128; no MPS / MRRS registers or checks.
* ECRC does not apply the §2.7.1 rule about the two "hint" bits being forced for the calculation.

### Data Link Layer (Ch 3)
* Power-management DLLPs (`PM_Enter_L1`, `PM_Enter_L23`, `PM_Request_Ack`,
  `PM_Active_State_Request_L1`), Vendor-Specific DLLP, NOP DLLP.
* No formal FC-initialization timeout / retry state machine.

### Physical Layer / LTSSM (Ch 4)
* **L0s, L1, L1 PM substates, L2 / L3 — not in the LTSSM state enum.** No ASPM. No Beacon / wake.
* **Gen3 equalization** (`Recovery.Equalization` phases 0–3) — not implemented; the link changes
  rate without it.
* **8b/10b (Gen1/Gen2)** — a stub. The PHY model is 128b/130b at all speeds.
* SKP ordered sets are not inserted into the data stream; no clock-tolerance compensation.
* Compliance-pattern generation is minimal; lane reversal / polarity inversion, de-emphasis /
  preset selection — not modelled.
* The regression exercises only **Gen1 x1** by default; the Gen2/Gen3 speed-change and multi-lane
  code paths are implemented but not routinely exercised.

### Configuration & System (Ch 6, 7)
* The **PCIe Capability structure (0x40–0x7F) is not populated** — the Capability Pointer points to
  0x40 but `EP_Config_Space::init()` stops at the Type-0 header (0x3F). Device / Link
  Control-Status, MPS / MRRS, retrain, ASPM control — not functional.
* **AER capability** — named in comments (0x100–0x12F) but not built.
* **VC capability structure** — VC configuration is hard-coded, not software-programmable.
* Power Management capability, MSI / MSI-X, extended config space beyond the AER stub.
* Type-1 (bridge) header — a RAL class exists (`reg_block1.sv`) but the bench rejects any non-Type-0
  device.
* ARI, SR-IOV, ACS, LTR, PTM, DPC, Resizable BAR, Slot Capabilities / hot-plug.
* Root Complex constructs (RCRB, RCiEP, Root Complex Event Collector).

### Error handling (Ch 6.2)
* No AER logging / reporting, no `ERR_COR` / `ERR_NONFATAL` / `ERR_FATAL` messages, no first-error
  pointer / header log.
* No completion timeout, no poisoned-data propagation rules, no flow-control protocol-error
  checking, no receiver-overflow, no uncorrectable / correctable classification & masking.

---

## 4. Suggested fix priority

1. Decode `Length == 0 ⇒ 1024` in the TL monitor payload capture (4 sites) and in
   `RX_PCIe_LUT.generate_mem_cpl` → un-breaks the max-payload tests.
2. Add `report_phase` reconciliation to all three scoreboards: `uvm_error` if `pass_cnt == 0`,
   if any queue is undrained, or if `pending_reads` is non-empty → stops silent fake passes.
3. Delimit TLPs in the DLL monitor by header length / framing marker, not `dl_rx_valid` → fixes
   `B2B_*`.
4. Add completion-side checks to `Scoreboard_Top` (byte-count sum, address ordering, first
   `Lower Address`, final `Byte Count`, no missing / duplicate fragment, Requester ID + Tag).
5. Add the `.size()` check to `DL_Scoreboard.compare_tlp1/2`.
6. Give the LTSSM tests a real state-transition checker.
7. Fix the `arm()` string mismatches in `TL_Fmt_Rtype_Illegal_test` / `PHY_STP_Framing_Error_test`.
8. Model RCB / MPS / MRRS; then SKP OS; then Gen3 equalization.
