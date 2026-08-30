# Block-level Testplan — validity analysis & additions

Source: `PCIe_Protocol_DV_Master_Tracker.xlsx`, sheet **`Testplan`** (individual-block tests).
The **`Top Testplan`** sheet (30 full-flow tests, already implemented in `tests/Test.sv` /
`tests/Error_Tests.sv`) is **out of scope — not touched**.

These block tests are meant to exercise **one layer at a time**. They are enabled by the
layered-stimulus infrastructure (`stim_layer` = TL / DLL / MAC / PMA — see
`LAYERED_STIMULUS_PLAN.md`): a test injects pre-formed stimulus directly at the target layer's
sequencer and checks that layer's behaviour, instead of always starting at the TL.

Verdict key:

| Mark | Meaning |
|---|---|
| ✅ | Valid & implementable now (VIP supports it) |
| 🔁 | Valid, but **duplicates** an existing Top-Testplan test — implement only as a stricter block-level check |
| 📝 | Valid intent, but the **description in the sheet is a copy-paste placeholder** that doesn't match the name — needs the description rewritten first |
| ⚠️ | Valid PCIe scenario, but a **VIP gap** must be filled first (feature or hook missing) |
| ❌ | **Not implementable** — the VIP fundamentally does not model this |

---

## 1. Transaction Layer block (rows 1–27, owner: Abhishek G D)

| # | Testcase | Verdict | Note |
|---|---|---|---|
| 1 | `Single_Mem_Wr_Rd_3DW_test` | 🔁 | Identical to the existing Top-Testplan test (already **Pass**). Nothing to add. |
| 2 | `PCIe_TL_4DW_MWr_Basic` | ✅ | 4DW (64-bit) MWr. Block version = inject at TL, check `TL_MON` header decode (fmt=011, 4DW addr) + payload transported. Overlaps `Single_Mem_Wr_Rd_4DW_test` but as a pure-write field check it's distinct. |
| 3 | `PCIe_TL_3DW_MRd_Basic` | ✅ | Standalone 3DW MRd + CplD; check completion status / ReqID / Tag / Byte Count / Lower Address. Not covered standalone today. |
| 4 | `PCIe_TL_4DW_MRd_Basic` | ✅ | Same, 4DW. |
| 5 | `PCIe_TL_3DW_IOWr_Basic` | ✅ | IO Wr to BAR3. **Caveat:** VIP does not model IO write-data read-back (KNOWN_ISSUES #3) — test can only check the TLP transported + completion status. Add an `io_space` check to make it meaningful. |
| 6 | `PCIe_TL_3DW_IORd_Basic` | ✅ | IO Rd returns `io_space` data. Same caveat — verify the CplD payload equals `io_space[addr]`. |
| 7 | `PCIe_TL_3DW_CfgWr_type0` | ✅ | CfgWr0. Enumeration already exercises this; a dedicated field check (BDF, register#, BE-masked write into `cfg_mem`) is valid. |
| 8 | `PCIe_TL_3DW_CfgRd_type0` | ✅ | CfgRd0 + CplD; verify data == `cfg_mem[reg]`. |
| 9 | `PCIe_TL_CfgWr_3DW_type1` | ⚠️ | **Type-1 config.** `pcie_base_test` fatals on non-Type-0; `reg_block1.sv` exists but isn't built; `RX_PCIe_LUT` decodes `is_cfg1_wr` but has no Type-1 target. Need a minimal Type-1 responder + a base test that doesn't reject it. |
| 10 | `PCIe_TL_CfgRd_3DW_type1` | ⚠️ | Same as #9. |
| 11 | `PCIe_TL_Message_4DW_write` | ❌ | **Message TLPs are not implemented at all** — all `MSG_*` are enum'd with a print stub, no header packing, no routing, no EP handling. Description is also wrong ("driving the Cfg Write TLP"). Needs a full Message-TLP feature (routing modes, message code, EP terminate-at-receiver). |
| 12 | `PCIe_TL_TLP_Digest_FieldCheck` | ✅ | Positive ECRC/TD field check: TD=1 → ECRC DW appended, matches golden recompute (`Sequence_item::calculate_ecrc`). Complements `TL_ECRC_Error_test`. |
| 13 | `PCIe_TL_Error_Poison_FieldCheck` | 🔁 | Duplicates `TL_EP_Poison_test`. Block version: EP=1 with a *valid* ECRC, verify the EP bit is carried on the wire and the payload is not applied to memory. |
| 14 | `PCIe_TL_Address_Type_translated` | ⚠️/📝 | Name says "translated", description says AT=00 (**untranslated**) — mismatch. VIP carries the AT field but has **no ATS semantics** — the only checkable thing is "AT field survives transport". Low value unless an ATS model is added. |
| 15 | `PCIe_TL_Length_1DW_write` | ✅ | Length=1 write; verify 1-DW transfer. |
| 16 | `PCIe_TL_Length_1024DW_write` | ⚠️/📝 | Name says 1024, description says "2 to 4 DW". A real 1024-DW (Length==0) transfer hits **KNOWN_ISSUES #0** (Length==0 not decoded → payload dropped). Fix #0 first, then this is a strong max-payload field check. |
| 17 | `PCIe_TL_Length_random_payload_write` | 🔁/📝 | Description = "Length ≠ payload" which is `TL_Length_Mismatch_test`. If the intent is "random *valid* length", ✅ and easy. Clarify the name. |
| 18 | `PCIe_TL_MWrMRd_3DW_Basic` | 🔁 | Duplicate of `Single_Mem_Wr_Rd_3DW_test`. |
| 19 | `PCIe_TL_MWrMRd_4DW_Basic` | 🔁 | Duplicate of `Single_Mem_Wr_Rd_4DW_test`. |
| 20 | `PCIe_TL_FirstByte_Enable_Full` | ✅ | first_BE=1111; verify every byte written (`Scoreboard_Top::write_dw_with_be`). |
| 21 | `PCIe_TL_FirstByte_Enable_Partial` | ✅ | first_BE partial (e.g. 0011); verify only enabled bytes changed, others preserved. Good test — the mem model supports it. |
| 22 | `PCIe_TL_FirstByte_Enable_Invalid` | ⚠️ | first_BE=0000. On a Length>1 write this is malformed, but the VIP's BE check **allows 0000** (`inside {4'b0000, ...}`). For Length==1 it's a legal zero-length request. Either add the "0000 on multi-DW = malformed" rule, or reinterpret as a zero-length-transaction test. |
| 23 | `PCIe_TL_LastByte_Enable_Valid` | ✅ | multi-DW write, valid last_BE (e.g. 0111); verify last-DW partial write. |
| 24 | `PCIe_TL_LastByte_Enable_Invalid` | 📝 | Description is a copy-paste of a basic write. Intent: non-contiguous/gapped last_BE → malformed. VIP has the check (`TL_Bad_BE_test` covers first+last non-contiguous). ✅ once the description is fixed. |
| 25 | `PCIe_TL_Tag_Basic` | 📝 | Description is a generic 4DW write. Intent: multiple outstanding non-posted requests with distinct tags, each completion matched by tag (`TAG_Manager` + tag echo in CplD). ✅ once described properly — a genuinely useful test. |
| 26 | `PCIe_TL_Cpl_Mismatch` | ⚠️/📝 | Description is a generic read. Intent: a completion arrives with a Tag/Requester-ID that matches no outstanding request → the EP-side monitor / `Scoreboard_Top` "Unmatched CPL_DATA" path fires. **This is exactly what layered stimulus enables** — inject a bogus CplD at the RC DLL. ✅ with the DLL-inject infra + a check. |
| 27 | `PCIe_TL_Unsupported_Req` | 🔁/📝 | Description generic. Duplicates `TL_Unsupported_Request_test` (MRd to unclaimed addr → UR). |

**TL block net:** ~9 new implementable (2,3,4,5,6,7,8,12,15,20,21,23,25), 7 duplicates, 3 need VIP work
(9,10 Type-1 · 22 BE rule · 26 needs the inject checker), 1 impossible (11 Message), several
descriptions to rewrite.

---

## 2. Data Link Layer block (rows 29–44, owner: Sandeep H R)

| # | Testcase | Verdict | Note |
|---|---|---|---|
| 29 | `Replay_Buffer_Clear_On_Reset` | ⚠️ | Needs a mid-run reset injection hook (drop `RESET` / `rc_link_up`). The DLL FSM clears state in `DL_INACTIVE`; the test just needs a way to force it there and re-check. |
| 30 | `DLLP_ACK_Generation_Test` | ✅ | Send a valid TLP RC→EP, capture the EP's ACK DLLP on the wire, verify type + AckNak seq == last good seq. `DL_Scoreboard` DLLP compare already runs. |
| 31 | `DLLP_NAK_Generation_Test` | 🔁 | Overlaps `DLL_LCRC_Error_test`, but stronger: after the LCRC error, verify a **NAK DLLP** (not just "mismatch flagged") with the expected AckNak seq goes out. Worth adding. |
| 32 | `Sequence_Number_Increment_Test` | ✅ | Send N TLPs, capture seq numbers on the wire, verify 0,1,2,…,N-1 (wrap at 4096). |
| 33 | `Replay_Buffer_Storage_Test` | ⚠️ | Needs replay-buffer occupancy visibility. The debug `report_phase` summaries added in the debug pass give a start; a proper checker (outstanding count grows on send, shrinks on ACK) is small work. |
| 34 | `Replay_On_NAK_Test` | ✅ | **Layered stimulus makes this clean:** inject a NAK DLLP for seq=X at the EP→RC DLL, verify the RC retransmits seq=X from the replay buffer (same seq appears twice on the wire, `replay_num` increments). |
| 35 | `Replay_Timer_Expiry_Test` | 🔁 | Duplicates `DLL_Replay_Timer_test` — which is currently **failing with a real bug** (KNOWN_ISSUES). Blocked until that's fixed. |
| 36 | `LCRC_Generation_Test` | ✅ | Send a TLP, capture on the wire, recompute LCRC with `Sequence_item::calculate_lcrc` (the golden), compare. |
| 37 | `LCRC_Error_Detection_Test` | 🔁 | Duplicate of `DLL_LCRC_Error_test`. |
| 38 | `InitFC1_DLLP_Test` | ✅ | Run with `wait_link_up=0`, capture the InitFC1 (P/NP/Cpl) DLLPs during `DL_INIT_FC1`, verify type codes + advertised credit fields (PH/PD/NPH/NPD/CPLH/CPLD). |
| 39 | `InitFC2_DLLP_Test` | ✅ | Same for `DL_INIT_FC2`; verify FC2 follows FC1 and the state advances to `DL_ACTIVE` after. |
| 40 | `UpdateFC_DLLP_Test` | ✅ | Send a TLP (consumes credit), verify an UpdateFC DLLP goes out carrying the decremented credit for that VC (`FC_Manager::fc_update_ev`). |
| 41 | `Credit_Exhaustion_Test` | ⚠️ | Set the partner's advertised credits low, send TLPs until exhausted, verify the TL driver / `VC_Arbiter` **blocks** (no more TLPs on the wire) until an UpdateFC restores credit. May expose the FC-gating weakness (KNOWN_ISSUES #13) — which is a *good* thing to find. |
| 42 | `DL_Down_State_Test` | ⚠️ | Needs a link-down injection hook (LTSSM → Recovery/Detect, or force `rc_link_up=0`). Then verify `rc_dl_state → DL_INACTIVE`, `dl_up=0`. |
| 43 | `DL_Up_State_Test` | ✅ | Trivial positive: after link training verify `dl_up=1`, `dl_down=0`, DLCMSM reached `DL_ACTIVE` (the `DL_active_env` event). |
| 44 | `Bad_DLLP_Detection_Test` | ✅ | Inject a malformed DLLP (reserved type field, or 3-DW instead of 2) at the EP DLL via layered stimulus; verify the DLL monitor flags it. Complements `DLL_DLLP_CRC_Error_test` (that's the CRC case). |

**DLL block net:** ~9 implementable (30,32,34,36,38,39,40,43,44), 3 duplicates (35,37 + 31 partial),
~4 need hooks (29 reset, 33 replay visibility, 41 FC gating, 42 link-down).

---

## 3. Physical Layer — LTSSM sub-block (rows 46–56, owner: Pooja)

| # | Testcase | Verdict | Note |
|---|---|---|---|
| 46 | `pcie_detect_basic_entry_exit_test` | ✅ | VIP has `Detect.Quiet`/`Detect.Active`; verify Electrical Idle on TX, LinkUp=0, receiver detection. (Sheet marks **Done** — confirm whether it already exists.) |
| 47 | `pcie_polling_ts1_tx_ts2_handshake_test` | ✅ | VIP models Polling.Active TS1 burst → TS2. Verify ≥ (VIP-scaled) TS1 count, Link#/Lane#=PAD, TS2 handshake. |
| 48 | `pcie_configuration_lane_link_negotiation_l0_entry_test` | ⚠️ | Described for **x4**. VIP default is x1 (`NUM_LANES=1`). x1 version ✅; x4 needs `NUM_LANES=4` compile + the config lane-number logic exercised (likely bugs — never run). |
| 49 | `pcie_l0_normal_tlp_dllp_traffic_test` | ✅ | Verify TLPs/DLLPs only move in L0. |
| 50 | `pcie_recovery_ts1_ts2_idle_l0_return_test` | ⚠️ | VIP has the Recovery substates (RcvrLock/RcvrCfg/Speed/Idle) and enters Recovery on speed-change or the `ltssm_recovery_req` event. "Bit error in L0 triggers Recovery" needs a symbol-error injection hook that the LTSSM notices. Recovery-via-`ltssm_recovery_req` ✅ now; via bit-error ⚠️. |
| 51 | `pcie_l0s_eios_entry_fts_exit_test` | ❌ | **L0s is not in the LTSSM state enum.** No EIOS→L0s entry, no N_FTS exit. Needs new states + FTS handling. |
| 52 | `pcie_l1_aspm_handshake_entry_recovery_exit_test` | ❌ | **No L1 state, no ASPM/PM DLLPs** (`PM_Active_State_Request_L1`, `PM_Request_ACK`). |
| 53 | `pcie_l2_pme_turnoff_entry_detect_exit_test` | ❌ | **No L2 state, no PM messages** (`PME_Turn_Off`/`PME_TO_ACK`), **no `PM_Enter_L23` DLLP**. |
| 54 | `pcie_hot_reset_ts1_hr_bit_entry_detect_exit_test` | 🔁 | Overlaps `LTSSM_HotReset_test`. Block version = verify the HR bit (Symbol 5 bit 0) in the TX TS1s and the exit to Detect. ✅ as a stricter check. |
| 55 | `pcie_loopback_master_lb_bit_symbol_echo_test` | 🔁 | Overlaps `LTSSM_Loopback_test`. Block version = verify LB bit in TS1 + slave symbol echo. ✅ as a stricter check. |
| 56 | `pcie_disabled_link_disable_bit_sw_clear_test` | 🔁 | Overlaps `LTSSM_Disabled_test`. Block version = verify 16–32 TS1s with Disable Link bit + return to Detect after SW clears it. ✅ as a stricter check. |

**LTSSM net:** ~6 implementable (46,47,49,50-partial,54,55,56 — several as stricter versions of
existing), 1 needs multi-lane (48), **3 impossible without new states (51 L0s, 52 L1, 53 L2)**.

---

## 4. Physical Layer — Data Framing sub-block (rows 57–68, owner: Aravind)

The VIP's 128b/130b framing is **minimal**: sync headers (2'b10 data / 2'b01 OS), an STP-like token
(length/seq/`fcrc`), an SDP-like token, and an EDS-like marker. The full framing-token *grammar*
(SDS, EDB, "only EIOS/EIEOS/SKP after EDS", per-lane token alignment) is **not modelled**, and the
STP framing CRC (`fcrc`) is a stale field that is never computed or checked.

| # | Testcase | Verdict | Note |
|---|---|---|---|
| 57 | `Pcie_frame_Invalid_CRC_STP_field_test` | ⚠️ | VIP does not compute/check the STP framing CRC. Add framing-CRC compute + a monitor check first. |
| 58 | `Pcie_frame_Invalid_length_STP_field_test` | ⚠️ | STP length=0. Tied to KNOWN_ISSUES #0 and the MAC un-framer livelock hole. Fix those, then this is a clean detection test. |
| 59 | `Pcie_frame_continuous_STP_test` | ⚠️ | STP-after-STP. The MAC un-framer must be taught to flag "STP where data expected". |
| 60 | `Pcie_frame_continuous_SDP_test` | ⚠️ | SDP-after-SDP, same as #59 for DLLPs. |
| 61 | `Pcie_frame_IDL_STP_error_x2_test` | ⚠️ | **x2 link** — needs `NUM_LANES=2` + per-lane token logic. |
| 62 | `Pcie_frame_SDS_any_OS_error_test` | ❌ | No SDS token modelled. |
| 63 | `Pcie_frame_before_EDS_any_OS_error_test` | ⚠️ | Needs the "OS before EDS = error" grammar rule. |
| 64 | `Pcie_frame_EDS_Data_error_test` | ⚠️ | Needs "data after EDS = error" rule. |
| 65 | `Pcie_frame_EDS_OS_error_test` | ⚠️ | Needs "only EIEOS/EIOS/SKP after EDS" rule. |
| 66 | `Pcie_frame_differ_lane_differ_OS_test` | ⚠️ | Needs multi-lane + per-lane OS comparison. |
| 67 | `Pcie_frame_sync_header_error_test` | ✅* | Invalid sync header (00/11). Small add: the MAC monitor currently ignores non-10/01 headers — add an `else` that flags it. Then this is implementable. |
| 68 | `Pcie_frame_EDB_error_injection` | ❌ | No EDB (End Bad) token modelled. |

**Framing net:** essentially **all of these need framing-layer development first**. Only #67 is
close to implementable. This whole sub-block should be treated as a **VIP feature project** (build
a proper 128b/130b framing model + grammar checker) before the tests.

---

## 5. What the VIP fundamentally cannot test (as-is)

| Area | Missing | Tests blocked |
|---|---|---|
| **Message TLPs** | No packing / routing / handling | TL #11 |
| **Type-1 config** | No Type-1 target / bridge model | TL #9, #10 |
| **Address Translation Services** | AT field carried, no ATS semantics | TL #14 |
| **Power management** | No L0s / L1 / L2 states, no PM DLLPs, no PM messages | LTSSM #51, #52, #53 |
| **Framing grammar** | No SDS / EDB tokens, no ordered-set sequencing rules, no framing-CRC check | Framing #57–68 (most) |
| **Multi-lane** | Striping code exists but x1 only in practice | LTSSM #48 (x4), Framing #61, #66 (x2) |

---

## 6. Tests worth ADDING (not in the sheet)

The layered-stimulus infra + the existing VIP support these well and they fill real gaps:

### TL block
- `PCIe_TL_Attr_RO_NS_IDO_FieldCheck` — set each Attr bit, verify carried unchanged (ordering not enforced, but the field check is valid)
- `PCIe_TL_TC_FieldCheck` + `PCIe_TL_TC_to_VC_Mapping` — set TC 0–7, verify `map_tc_to_vc` routes to the configured VC
- `PCIe_TL_VC_Arbitration_Priority` — queue TLPs on VC0 + VC7, verify strict-priority order on the wire (`VC_Arbiter`)
- `PCIe_TL_MultiTag_Outstanding` — N concurrent MRd with distinct tags, all CplD matched by tag; then tag-pool exhaustion
- `PCIe_TL_CplD_Split_at_RCB` — large MRd, verify the EP splits CplD at `MAX_CPL_BYTES`, first fragment's Lower Address / Byte Count correct, fragments in address order (needs the completion-side checker from KNOWN_ISSUES #4)
- `PCIe_TL_ZeroLength_Read` — Length=1, all BE=0 (flush semantics)
- `PCIe_TL_CfgRd_BE_Masked` — CfgRd/CfgWr with partial BE

### DLL block
- `DLL_Duplicate_TLP_Ack_Drop` — inject a TLP with seq < NRS (already received) → verify EP ACKs and drops it (no double-apply)
- `DLL_SeqGap_Nak` — inject a TLP with seq > NRS (gap) → verify NAK with `NRS-1`
- `DLL_Ack_For_Unsent_Seq` — inject an ACK for a seq never sent → verify RC ignores / flags it
- `DLL_UpdateFC_Cadence` — verify UpdateFC DLLPs are sent at the required interval, not just on change

### MAC block (all enabled by `STIM_MAC`)
- `MAC_STP_Length_FieldCheck` — inject a framed packet, verify the STP the MAC adds has length == DW count
- `MAC_ByteStripe_Reversible` — inject, capture RC-TX PHY words, un-stripe, verify == input
- `MAC_TS1_TS2_FieldCheck` — verify Rate ID / Link# / Lane# fields in the TS1/TS2 the LTSSM drives
- `MAC_Scrambler_LFSR_PerLane` — verify the per-lane 23-bit LFSR advances per the spec seed

### PMA / PCS block (`STIM_PMA`)
- `PMA_SyncHeader_Correctness` — 2'b10 on data blocks, 2'b01 on OS blocks
- `PMA_Serialize_Deserialize_BitExact` — inject 130-bit blocks, capture the far-end reassembly, verify bit-exact
- `PMA_Scrambler_Seed_PerLane` — verify each lane's scrambler starts from the correct seed

### Cross-layer (the Phase-3 smoke set, promoted to real tests)
- `Layer_SameTLP_TL_vs_DLL_vs_MAC` — inject the identical TLP at each layer, assert the EP receives an identical TLP each way (proves the layered infra + each layer's add-on is correct)

---

## 7. Recommended build order

1. **TL block, group A (no VIP change):** 2,3,4,7,8,12,15,20,21,23  +  new: Attr, TC, VC-arb, MultiTag
2. **DLL block, group A (no VIP change, uses `STIM_DLL`):** 30,32,34,36,38,39,40,43,44  +  new: Duplicate-TLP, SeqGap-Nak
3. **IO data check** (small VIP add) → then TL 5,6
4. **Completion-side checker** (KNOWN_ISSUES #4) → then TL 3,4,25,26 and new CplD-split
5. **MAC block** (after the `STIM_MAC` run-verify) → MAC group + LTSSM 46,47,49,54,55,56
6. **Hooks:** reset-inject, link-down-inject → DLL 29,42 ; FC-gating check → DLL 41
7. **Framing model project** → Framing sub-block (large, separate effort)
8. **Deferred / needs new features:** Type-1 cfg, Message TLPs, L0s/L1/L2, multi-lane

> Everything in steps 1–2 is buildable **right now** (compile-only; run-verify when a simulator
> license frees up). That's ~20 real block tests without touching the VIP.
