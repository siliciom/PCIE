# Test Catalog

30 tests, defined in `tests/Test.sv` (functional) and `tests/Error_Tests.sv` (negative /
error-injection). Every test extends `pcie_base_test`, so it always starts with:

* wait for the Data Link layer to reach `DL_ACTIVE` on **both** RC and EP
* `do_enumeration()` — CfgRd VID/DID, header type, read+size+assign all 6 BARs, enable the
  Command register (Mem + IO + Bus Master)

then runs its own stimulus.

Run one: `vsim -c -do "set only <NAME>; do run_all.do"` (from `pcie_gen3/sim/`).

---

## Functional tests (`tests/Test.sv`)

| Test | Stimulus | Checked by | Notes |
|---|---|---|---|
| `Single_Mem_Wr_Rd_3DW_test` | 1× MWr + 1× MRd, BAR0 (32-bit mem → 3DW header), length 100 DW, TD=1 | `Scoreboard_Top` transport + memory read-data | baseline |
| `Single_Mem_Wr_Rd_4DW_test` | 1× MWr + 1× MRd, BAR1 (64-bit mem → 4DW header), length 34 DW | same | baseline |
| `Multiple_Mem_Wr_Rd_3DW_test` | many MWr+MRd pairs at randomised offsets in BAR0 | same | healthy `mem_pass_cnt` |
| `Multiple_Mem_Wr_Rd_4DW_test` | many MWr+MRd pairs, BAR1 | same | healthy `mem_pass_cnt` |
| `Single_Mem_Wr_Rd_3DW_Max_payload_test` | 1× MWr + 1× MRd, **length = 0 (⇒ 1024 DW / 4 KB)**, BAR0, replay disabled | same | **FAILING** — see KNOWN_ISSUES #0 |
| `Single_Mem_Wr_Rd_4DW_Max_payload_test` | 1× MWr + 1× MRd, length = 0 (1024 DW), BAR1, replay disabled | same | passes at Gen1 only because the read produces no completion — **fake pass**, KNOWN_ISSUES #0/#1 |
| `Multiple_Mem_Wr_Rd_3DW_rand_length_test` | many MWr+MRd, random length | same | |
| `B2B_Mem_Wr_Rd_3DW_test` | back-to-back TLPs (no idle gap between them), BAR0 | same + `DL_Scoreboard` | **FAILING** — DLL monitor mis-delimits gapless TLPs, KNOWN_ISSUES |
| `B2B_Mem_Wr_Rd_4DW_test` | back-to-back TLPs, BAR1 | same | |
| `Single_IO_Wr_Rd_3DW_test` | 1× IOWr + 1× IORd, BAR3 (IO BAR) | `Scoreboard_Top` **transport only** | IO read-data is **not** checked (KNOWN_ISSUES #3) |
| `Multiple_IO_Wr_Rd_3DW_test` | many IO Wr/Rd | transport only | **FAILING** — EP returns UR completions |
| `B2B_IO_Wr_Rd_3DW_test` | back-to-back IO Wr/Rd | transport only | |
| `LTSSM_Disabled_test` | set Link Disable on RC+EP, wait past the LTSSM timeouts | *(no checker)* — passes if nothing errors | KNOWN_ISSUES #2 (no LTSSM assertion) |
| `LTSSM_Loopback_test` | direct LTSSM to Loopback, then direct Loopback exit | *(no checker)* | KNOWN_ISSUES #2 |
| `LTSSM_HotReset_test` | directed Hot Reset on RC | *(no checker)* | KNOWN_ISSUES #2 |

---

## Negative / error-injection tests (`tests/Error_Tests.sv`)

Recipe: `catcher.reset()` → `catcher.arm("<ID>", "<substr>")` → drive **one** corrupted
transaction → wait a bounded window → `PASS` if `catcher.hit_cnt > 0` else
`uvm_error("TEST_RESULT", "FAIL: ...")`. The armed error is demoted to `EXPECTED_<ID>` info.

| Test | Injection | Expected checker (armed ID) | Notes |
|---|---|---|---|
| `TL_ECRC_Error_test` | `ERR_ECRC` — bit-flip the ECRC digest on a MWr | `RX_TL_MONITOR` / "ECRC MISMATCH" | |
| `TL_Length_Mismatch_test` | `ERR_LEN_MISMATCH` — header Length ≠ DWs actually sent | `MALFORMED_TLP` / "ERR_LENGTH" | |
| `TL_IO_Length_test` | `ERR_IO_LEN` — IO read with Length = 2 (spec: must be 1) | `MALFORMED_TLP` / "IO/CFG" | |
| `TL_CFG_Length_test` | `ERR_CFG_LEN` — Config read with Length = 2 | `MALFORMED_TLP` / "IO/CFG" | |
| `TL_Fmt_Rtype_Illegal_test` | `ERR_FMT_RTYPE` — fmt = reserved encoding | `MALFORMED_TLP` / "Reserved fmt encoding" | **FAILING** — the monitor flags it but with a *different* message string, so the armed substring never matches (KNOWN_ISSUES) |
| `TL_Bad_BE_test` | `ERR_BYTE_EN` — non-contiguous first/last byte enables | `MALFORMED_TLP` / "byte-enable" | |
| `TL_EP_Poison_test` | `ERR_EP_POISON` — EP=1 on a MWr | `RX_TL_MONITOR` / "POISONED TLP" | payload must not reach `mem_space` |
| `TL_Unsupported_Request_test` | plain MRd to an address outside every BAR | `TX_TL_MONITOR` / "UNSUPPORTED_REQ" | completion forced to UR |
| `TL_Completer_Abort_test` | plain MRd to a reserved trigger offset inside BAR0 | `TX_TL_MONITOR` / "COMPLETER_ABORT" | completion forced to CA |
| `DLL_LCRC_Error_test` | `ERR_LCRC` on the RC DLL driver — corrupt the LCRC | `RX_DLL_MON` / "LCRC MISMATCH" | expected effect: Nak + replay (replay itself is **not** verified — KNOWN_ISSUES) |
| `DLL_DLLP_CRC_Error_test` | `ERR_DLLP_CRC` on the EP DLL driver — corrupt an Ack's CRC-16 | `TX_DLL_MON` / "CRC" | |
| `DLL_Seq_Num_test` | `ERR_SEQ_NUM` — RC skips a sequence number | `SEQ_CHECK` / "Out-of-order" | |
| `PHY_STP_Framing_Error_test` | `ERR_STP` — drop the packet-type / framing marker for one burst | `PHY_FRAMING` / "framing token corrupted" | **FAILING** — the corruption surfaces as a seq-number skip, not the framing path the test watches (KNOWN_ISSUES) |
| `DLL_Replay_Num_Rollover_test` | `ERR_LCRC` held on — RC keeps Nak'ing, forcing 4+ replays of one packet | `RX_DLL_MON` / "LCRC MISMATCH" **or** `REPLAY` / "exceeded replay limit" | passes on the LCRC hit alone; the "exceeded replay limit" checker is **never observed to fire** — effectively a fake pass (KNOWN_ISSUES) |
| `DLL_Replay_Timer_test` | withhold one Ack past `rc_replay_timer_limit` (12429 DLL clocks) | `REPLAY` / "exceeded replay limit" | **FAILING** — 2000+ cascading errors; genuine DUT/model replay bug |

---

## Last recorded regression (`regr_cov1`, Gen1)

**24 / 30 PASS.**

Failing: `Single_Mem_Wr_Rd_3DW_Max_payload_test`, `B2B_Mem_Wr_Rd_3DW_test`,
`Multiple_IO_Wr_Rd_3DW_test`, `TL_Fmt_Rtype_Illegal_test`, `PHY_STP_Framing_Error_test`,
`DLL_Replay_Timer_test`.

See `KNOWN_ISSUES.md` for the root cause of each, and for which of the *passing* tests are not
actually verifying what their name implies.
