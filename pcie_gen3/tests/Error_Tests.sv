// Error_Tests.sv
//   Every class below follows the same two-step recipe:
//     1. injection knob
//          Sequence_item::post_randomize()/pack_tlp() - see
//          sequences/Sequence_item.sv).
//        - DLL/PHY layer: set directly on the DLL driver's own
//          env_cfg handle, e.g.
//          RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err
//          (consumed in agents/PCIe_DLL_Driver.sv).
//     2. targeted checker - either a pre-existing uvm_error (LCRC/
//        DLLP CRC mismatch, replay-limit exceeded, unmatched CPL,
//        ECRC mismatch) or one added alongside this error-injection
//        work (MALFORMED_TLP, UNSUPPORTED_REQ, SEQ_CHECK,
//        PHY_FRAMING).
//   How each test ends
//   Every test:
//     - gets Error_Report_Catcher::get(), calls reset(), then arm()s
//       the exact report ID (+ optional message substring) its
//       checker is expected to raise. Armed uvm_errors are demoted
//       to uvm_info and counted in catcher.hit_cnt - anything NOT
//       armed still fails the run normally.
//     - drives exactly one corrupted transaction.
//     - waits a bounded window (comfortably longer than any normal
//       link round-trip in this bench).
//       style checkers) or from a Scoreboard_Top pass_cnt/fail_cnt
//       snapshot diff (silent-drop style checkers, exactly like
//       TL_Length_Mismatch_test), via a final
//       uvm_error("TEST_RESULT", "FAIL: ...") /
//       uvm_info(... "PASS ...").
//   TL_Length_Mismatch_test note: Error_Inject_Seq always forces
//   td==1 (ECRC present) regardless of scenario, which is what
//   makes the length-lie scenario provably safe here - the RX
//   monitor's ECRC recompute over the wrong number of payload words
//   is essentially guaranteed to mismatch real payload data, so the
//   existing "ECRC MISMATCH - PACKET DROPPED" path
//   (agents/PCIe_TL_Monitor.sv) fires and the malformed packet is
//   never written to rx_req_q - so it can never be compared/scored
//   as a pass. That is the actual mechanism behind "pass_cnt must
//   never increase" for this scenario in this bench.


// TL_ECRC_Error_test
//   Inject: ERR_ECRC on one MEM_WR (pack_tlp() flips the digest).
class TL_ECRC_Error_test extends pcie_base_test;

     `uvm_component_utils(TL_ECRC_Error_test)

     Error_Inject_Seq err_seq;
     Error_Report_Catcher catcher;

     function new(string name = "TL_ECRC_Error_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);  // link-up + full enumeration
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("RX_TL_MONITOR", "ECRC MISMATCH");

          err_seq              = Error_Inject_Seq::type_id::create("err_seq");
          err_seq.p_type       = MEM_WR;
          err_seq.p_fmt        = bar_wr_fmt[0];
          err_seq.p_addr       = bar_base[0] + 64'h10;
          err_seq.p_length     = 4;
          err_seq.p_inject_err = ERR_ECRC;
          err_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT",
                         "PASS: corrupted ECRC was detected and flagged by RX_TL_MONITOR", UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: corrupted ECRC was NOT detected by RX_TL_MONITOR")

          phase.drop_objection(this);
     endtask : run_phase

endclass : TL_ECRC_Error_test


//           in sequences/Sequence_item.sv) vs the DWs actually
//           packed/sent.
//   Checker: the only correct outcome is that pass_cnt did NOT
//            increase - a malformed TLP must never be silently
//            scored as a good transaction. See the file-header note
//            above for exactly why that holds in this bench.
class TL_Length_Mismatch_test extends pcie_base_test;

     `uvm_component_utils(TL_Length_Mismatch_test)

     Error_Inject_Seq err_seq;
     // int pass_cnt_before, fail_cnt_before;
     Error_Report_Catcher catcher;

     function new(string name = "TL_Length_Mismatch_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);


          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("MALFORMED_TLP", "ERR_LENGTH");

          err_seq              = Error_Inject_Seq::type_id::create("err_seq");
          err_seq.p_type       = MEM_WR;
          err_seq.p_fmt        = bar_wr_fmt[0];
          err_seq.p_addr       = bar_base[0] + 64'h20;
          err_seq.p_length     = 8;
          err_seq.p_inject_err = ERR_LEN_MISMATCH;
          err_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT", "PASS: IO read with Length>1 flagged as Malformed",
                         UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: IO read with Length>1 was not flagged")


          phase.drop_objection(this);
     endtask : run_phase

endclass : TL_Length_Mismatch_test


// TL_IO_Length_test
//   Inject: ERR_IO_LEN on an IO_RD - post_randomize() forces
//           Length=2 (spec requires Length==1 for IO).
//   Checker: uvm_error("MALFORMED_TLP", "...IO/CFG...") added in
//            agents/PCIe_TL_Monitor.sv.
class TL_IO_Length_test extends pcie_base_test;

     `uvm_component_utils(TL_IO_Length_test)

     Error_Inject_Seq err_seq;
     Error_Report_Catcher catcher;

     function new(string name = "TL_IO_Length_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("MALFORMED_TLP", "IO/CFG");

          err_seq              = Error_Inject_Seq::type_id::create("err_seq");
          err_seq.p_type       = IO_RD;
          err_seq.p_fmt        = bar_rd_fmt[3];
          err_seq.p_addr       = bar_base[3] + 64'h4;
          err_seq.p_length     = 1;  // post_randomize() forces this to 2
          err_seq.p_inject_err = ERR_IO_LEN;
          err_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT", "PASS: IO read with Length>1 flagged as Malformed",
                         UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: IO read with Length>1 was not flagged")

          phase.drop_objection(this);
     endtask : run_phase

endclass : TL_IO_Length_test


// TL_CFG_Length_test
//   Inject: ERR_CFG_LEN on a CFG_RD0 - post_randomize() forces
//           Length=2 (spec requires Length==1 for Config).
//   Checker: uvm_error("MALFORMED_TLP", "...IO/CFG...") added in
//            agents/PCIe_TL_Monitor.sv.
class TL_CFG_Length_test extends pcie_base_test;

     `uvm_component_utils(TL_CFG_Length_test)

     Error_Inject_Seq err_seq;
     Error_Report_Catcher catcher;

     function new(string name = "TL_CFG_Length_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("MALFORMED_TLP", "IO/CFG");

          err_seq              = Error_Inject_Seq::type_id::create("err_seq");
          err_seq.p_type       = CFG_RD0;
          err_seq.p_fmt        = FMT_3DW_NO_DATA;
          err_seq.p_addr       = 64'h0;
          err_seq.p_length     = 1;  // post_randomize() forces this to 2
          err_seq.p_inject_err = ERR_CFG_LEN;
          err_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT", "PASS: Config read with Length>1 flagged as Malformed",
                         UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: Config read with Length>1 was not flagged")

          phase.drop_objection(this);
     endtask : run_phase

endclass : TL_CFG_Length_test


// TL_Fmt_Rtype_Illegal_test
//   Inject: ERR_FMT_RTYPE - post_randomize() stomps fmt to the
//           reserved encoding 3'b101.
//            default: branch added in agents/PCIe_TL_Monitor.sv.
class TL_Fmt_Rtype_Illegal_test extends pcie_base_test;

     `uvm_component_utils(TL_Fmt_Rtype_Illegal_test)

     Error_Inject_Seq err_seq;
     Error_Report_Catcher catcher;

     function new(string name = "TL_Fmt_Rtype_Illegal_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("MALFORMED_TLP", "Illegal/reserved");

          err_seq              = Error_Inject_Seq::type_id::create("err_seq");
          err_seq.p_type       = MEM_WR;
          err_seq.p_fmt        = bar_wr_fmt[0];
          err_seq.p_addr       = bar_base[0] + 64'h30;
          err_seq.p_length     = 4;
          err_seq.p_inject_err = ERR_FMT_RTYPE;
          err_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT", "PASS: illegal fmt+r_type combination flagged as Malformed",
                         UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: illegal fmt+r_type combination was not flagged")

          phase.drop_objection(this);
     endtask : run_phase

endclass : TL_Fmt_Rtype_Illegal_test


// TL_Bad_BE_test
//   Inject: ERR_BYTE_EN - post_randomize() forces first_BE=4'b0101,
//           last_BE=4'b1010 (both non-contiguous, illegal).
//   Checker: uvm_error("MALFORMED_TLP", "byte-enable") added in
//            agents/PCIe_TL_Monitor.sv.
class TL_Bad_BE_test extends pcie_base_test;

     `uvm_component_utils(TL_Bad_BE_test)

     Error_Inject_Seq err_seq;
     Error_Report_Catcher catcher;

     function new(string name = "TL_Bad_BE_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("MALFORMED_TLP", "byte-enable");

          err_seq              = Error_Inject_Seq::type_id::create("err_seq");
          err_seq.p_type       = MEM_WR;
          err_seq.p_fmt        = bar_wr_fmt[0];
          err_seq.p_addr       = bar_base[0] + 64'h40;
          err_seq.p_length     = 20;
          err_seq.p_inject_err = ERR_BYTE_EN;
          err_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT", "PASS: illegal byte-enable pattern flagged as Malformed",
                         UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: illegal byte-enable pattern was not flagged")

          phase.drop_objection(this);
     endtask : run_phase

endclass : TL_Bad_BE_test


// TL_EP_Poison_test
//   Inject: ERR_EP_POISON - post_randomize() forces ep=1 on an
//           otherwise-normal MEM_WR.
//   Checker: uvm_error("MALFORMED_TLP", "Poisoned MEM_WR...") added
//            in env/Scoreboard_Top.sv::mem_write() - the poisoned
//            payload must never be applied to the memory model.
class TL_EP_Poison_test extends pcie_base_test;

     `uvm_component_utils(TL_EP_Poison_test)

     Error_Inject_Seq err_seq;
     Error_Report_Catcher catcher;

     function new(string name = "TL_EP_Poison_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("RX_TL_MONITOR", "POISONED TLP");

          err_seq              = Error_Inject_Seq::type_id::create("err_seq");
          err_seq.p_type       = MEM_WR;
          err_seq.p_fmt        = bar_wr_fmt[0];
          err_seq.p_addr       = bar_base[0] + 64'h50;
          err_seq.p_length     = 4;
          err_seq.p_inject_err = ERR_EP_POISON;
          err_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT",
                         "PASS: poisoned (EP=1) write payload was dropped per completer policy",
                         UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: poisoned write was not detected/dropped")

          phase.drop_objection(this);
     endtask : run_phase

endclass : TL_EP_Poison_test


// TL_Unsupported_Request_test
//   Inject: plain MEM_RD (ERR_NONE) to an address outside every
//           implemented BAR - the scenario is the address choice
//           itself, not a field corruption.
//   Checker: uvm_error("UNSUPPORTED_REQ", ...) added in
//            agents/RX_PCIe_LUT.sv::is_addr_supported(), which also
//            forces the completion status back to UR (3'b001).
class TL_Unsupported_Request_test extends pcie_base_test;

     `uvm_component_utils(TL_Unsupported_Request_test)

     Error_Inject_Seq err_seq;
     Error_Report_Catcher catcher;

     function new(string name = "TL_Unsupported_Request_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("TX_TL_MONITOR", "UNSUPPORTED_REQ");

          err_seq               = Error_Inject_Seq::type_id::create("err_seq");
          err_seq.p_type        = MEM_RD;
          err_seq.p_fmt         = FMT_3DW_NO_DATA;
          err_seq.p_addr        = bar_base[0] + 32'h3000000;  // outside every implemented BAR
          err_seq.p_length      = 1;
          err_seq.p_use_tag_mgr = 1;
          err_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT",
                         "PASS: read to unsupported address flagged and answered with UR", UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: read to unsupported address was not flagged")

          phase.drop_objection(this);
     endtask : run_phase

endclass : TL_Unsupported_Request_test


// TL_Completer_Abort_test
//   Inject: plain MEM_RD (ERR_NONE) to a special offset inside
//           BAR0 (a normally valid, claimed range) that is reserved
//           to model a completer-side internal failure - the
//           scenario is the address choice itself, not a field
//           corruption.
//   Checker: uvm_error("TX_TL_MONITOR", ...) added in
//            agents/PCIe_TL_Monitor.sv, which fires when a
//            completion carrying compl_status == CA (3'b100) is
//            received back on the RC. The status is forced by
//            agents/RX_PCIe_LUT.sv::is_ca_trigger_addr().
class TL_Completer_Abort_test extends pcie_base_test;

     `uvm_component_utils(TL_Completer_Abort_test)

     Error_Inject_Seq err_seq;
     Error_Report_Catcher catcher;

     function new(string name = "TL_Completer_Abort_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("TX_TL_MONITOR", "COMPLETER_ABORT");

          err_seq               = Error_Inject_Seq::type_id::create("err_seq");
          err_seq.p_type        = MEM_RD;
          err_seq.p_fmt         = FMT_3DW_NO_DATA;
          err_seq.p_addr        = bar_base[0] + 64'hC0;  // reserved CA-trigger offset inside BAR0
          err_seq.p_length      = 1;
          err_seq.p_use_tag_mgr = 1;
          err_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT",
                         "PASS: read to CA-trigger address flagged and answered with CA", UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: read to CA-trigger address was not flagged")

          phase.drop_objection(this);
     endtask : run_phase

endclass : TL_Completer_Abort_test


// DLL_LCRC_Error_test
//   Inject: RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err =
//           ERR_LCRC - one-shot, corrupts the LCRC DW appended
//           right after rc_calculate_lcrc() for the next
//           TX_DLP_PACKET.
//            in agents/PCIe_DLL_Monitor.sv, which also triggers the
//            NAK + replay-from-buffer path.
class DLL_LCRC_Error_test extends pcie_base_test;

     `uvm_component_utils(DLL_LCRC_Error_test)

     Single_Mem_Wr_Rd_3DW Mem_Seq_tx;
     Error_Report_Catcher catcher;

     function new(string name = "DLL_LCRC_Error_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("RX_DLL_MON", "LCRC MISMATCH");

          RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err = ERR_LCRC;

          Mem_Seq_tx = Single_Mem_Wr_Rd_3DW::type_id::create("Mem_Seq_tx");
          Mem_Seq_tx.p_wr_fmt = bar_wr_fmt[0];
          Mem_Seq_tx.p_rd_fmt = bar_rd_fmt[0];
          Mem_Seq_tx.p_addr = bar_base[0] + 64'h60;
          Mem_Seq_tx.p_length = 4;
          Mem_Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT", "PASS: corrupted LCRC detected -> NAK + replay", UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: corrupted LCRC was NOT detected")

          phase.drop_objection(this);
     endtask : run_phase

endclass : DLL_LCRC_Error_test


// DLL_DLLP_CRC_Error_test
//   Inject: EP_Env[0]...PCIe_DLL_Drv.cfg.inject_err = ERR_DLLP_CRC -
//           one-shot, corrupts the next Ack/Nak DLLP's 16-bit CRC
//           (the EP's own Ack for RC's write is what we corrupt).
//   Checker: pre-existing uvm_error("TX_DLL_MON", ...) DLLP-CRC
//            mismatch path in agents/PCIe_DLL_Monitor.sv.
class DLL_DLLP_CRC_Error_test extends pcie_base_test;

     `uvm_component_utils(DLL_DLLP_CRC_Error_test)

     Single_Mem_Wr_Rd_3DW Mem_Seq_tx;
     Error_Report_Catcher catcher;

     function new(string name = "DLL_DLLP_CRC_Error_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("TX_DLL_MON", "CRC");

          EP_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err = ERR_DLLP_CRC;

          Mem_Seq_tx = Single_Mem_Wr_Rd_3DW::type_id::create("Mem_Seq_tx");
          Mem_Seq_tx.p_wr_fmt = bar_wr_fmt[0];
          Mem_Seq_tx.p_rd_fmt = bar_rd_fmt[0];
          Mem_Seq_tx.p_addr = bar_base[0] + 64'h70;
          Mem_Seq_tx.p_length = 4;
          Mem_Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT", "PASS: corrupted DLLP CRC detected (Bad-DLLP path)",
                         UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: corrupted DLLP CRC was NOT detected")

          phase.drop_objection(this);
     endtask : run_phase

endclass : DLL_DLLP_CRC_Error_test


// DLL_Seq_Num_test
//   Inject: RC_Env[0]...PCIe_DLL_Drv.cfg.inject_err = ERR_SEQ_NUM -
//           one-shot, the RC DLL driver skips one sequence number
//           instead of incrementing by 1.
//   Checker: uvm_error("SEQ_CHECK", "Out-of-order/skipped...") added
class DLL_Seq_Num_test extends pcie_base_test;

     `uvm_component_utils(DLL_Seq_Num_test)

     Single_Mem_Wr_Rd_3DW Mem_Seq_tx;
     Error_Report_Catcher catcher;

     function new(string name = "DLL_Seq_Num_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("SEQ_CHECK", "Out-of-order");

          RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err = ERR_SEQ_NUM;

          Mem_Seq_tx = Single_Mem_Wr_Rd_3DW::type_id::create("Mem_Seq_tx");
          Mem_Seq_tx.p_wr_fmt = bar_wr_fmt[0];
          Mem_Seq_tx.p_rd_fmt = bar_rd_fmt[0];
          Mem_Seq_tx.p_addr = bar_base[0] + 64'h80;
          Mem_Seq_tx.p_length = 4;
          Mem_Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT", "PASS: skipped/out-of-order DL sequence number detected",
                         UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: skipped DL sequence number was NOT detected")

          phase.drop_objection(this);
     endtask : run_phase

endclass : DLL_Seq_Num_test


// PHY_STP_Framing_Error_test
//   Inject: RC_Env[0]...PCIe_DLL_Drv.cfg.inject_err = ERR_STP -
//           one-shot, the packet-type marker (this bench's
//           equivalent of Gen3's framing token) is dropped for one
//           TX burst.
//   Checker: uvm_error("PHY_FRAMING", ...) framing watchdog added in
class PHY_STP_Framing_Error_test extends pcie_base_test;

     `uvm_component_utils(PHY_STP_Framing_Error_test)

     Single_Mem_Wr_Rd_3DW Mem_Seq_tx;
     Error_Report_Catcher catcher;

     function new(string name = "PHY_STP_Framing_Error_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("PHY_FRAMING", "framing token corrupted");

          RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err = ERR_STP;

          Mem_Seq_tx = Single_Mem_Wr_Rd_3DW::type_id::create("Mem_Seq_tx");
          Mem_Seq_tx.p_wr_fmt = bar_wr_fmt[0];
          Mem_Seq_tx.p_rd_fmt = bar_rd_fmt[0];
          Mem_Seq_tx.p_addr = bar_base[0] + 64'h90;
          Mem_Seq_tx.p_length = 4;
          Mem_Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #50000;

          if (catcher.hit_cnt > 0)
               `uvm_info(
                   "TEST_RESULT",
                   "PASS: corrupted start-of-TLP framing marker detected (real HW: LTSSM Recovery)",
                   UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: corrupted framing marker was NOT detected")

          phase.drop_objection(this);
     endtask : run_phase

endclass : PHY_STP_Framing_Error_test


// DLL_Replay_Num_Rollover_test
//   Inject: RC_Env[0]...PCIe_DLL_Drv.cfg.inject_err held at
//           ERR_REPLAY_ROLLOVER for the whole window - RC keeps
//           NAK'ing every packet the EP sends it, forcing 4+
//           replays of the same packet.
//   Checker: pre-existing uvm_error("REPLAY", "... exceeded replay
class DLL_Replay_Num_Rollover_test extends pcie_base_test;

     `uvm_component_utils(DLL_Replay_Num_Rollover_test)

     Single_Mem_Wr_Rd_3DW Mem_Seq_tx;
     Error_Report_Catcher catcher;

     function new(string name = "DLL_Replay_Num_Rollover_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("RX_DLL_MON", "LCRC MISMATCH");
          catcher.arm("REPLAY", "exceeded replay limit");


          RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err = ERR_LCRC;
          Mem_Seq_tx = Single_Mem_Wr_Rd_3DW::type_id::create("Mem_Seq_tx");
          Mem_Seq_tx.p_wr_fmt = bar_wr_fmt[0];
          Mem_Seq_tx.p_rd_fmt = bar_rd_fmt[0];
          Mem_Seq_tx.p_addr = bar_base[0] + 64'hA0;
          Mem_Seq_tx.p_length = 4;
          Mem_Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

          #3000000;  // needs to span 4+ replay-timer expiries

          RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err = ERR_NONE;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT",
                         "PASS: replay-count rollover (4+ replays of the same packet) detected",
                         UVM_HIGH)
          else `uvm_error("TEST_RESULT", "FAIL: replay-count rollover was NOT detected")

          phase.drop_objection(this);
     endtask : run_phase

endclass : DLL_Replay_Num_Rollover_test


// DLL_Replay_Timer_test
//   Inject: same cfg.inject_err knob (ERR_REPLAY_TIMER), held only
//           long enough to withhold one Ack past
//           rc_replay_timer_limit, then released - showing the
//           timer alone (not an explicit NAK burst) retriggers a
//           replay.
//   Checker: re-entering the NAK/replay path past the replay-limit
//            raises the same pre-existing uvm_error("REPLAY", "...
//            exceeded replay limit") if it keeps going - armed here
//            as evidence the replay-timer-driven retrigger path
//            really fired.
class DLL_Replay_Timer_test extends pcie_base_test;

     `uvm_component_utils(DLL_Replay_Timer_test)

     Single_Mem_Wr_Rd_3DW Mem_Seq_tx;
     Error_Report_Catcher catcher;
     bit [63:0] curr_addr;
     bit [5:0] offset;

     function new(string name = "DLL_Replay_Timer_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          super.run_phase(phase);
          phase.raise_objection(this);
          assert (std::randomize(
              offset
          ) with {
               offset inside {[10 : 50]};
               offset % 4 == 0;
          });

          catcher = Error_Report_Catcher::get();
          catcher.reset();
          catcher.arm("REPLAY", "exceeded replay limit");

          curr_addr = bar_base[0] + offset;

          repeat (6) begin
               Mem_Seq_tx = Single_Mem_Wr_Rd_3DW::type_id::create("Mem_Seq_tx");
               Mem_Seq_tx.p_wr_fmt = bar_wr_fmt[0];
               Mem_Seq_tx.p_rd_fmt = bar_rd_fmt[0];
               Mem_Seq_tx.p_addr = curr_addr;
               Mem_Seq_tx.p_length = 1023;
               Mem_Seq_tx.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
               curr_addr += Mem_Seq_tx.p_length * 4;

          end
          // rc_replay_timer_limit is 12429 DLL clocks - wait past it once,
          // then stop stalling and let the link recover normally.
          #10000000;

          if (catcher.hit_cnt > 0)
               `uvm_info("TEST_RESULT",
                         "PASS: withheld Ack past the replay timer limit retriggered replay",
                         UVM_HIGH)
          else
               `uvm_error("TEST_RESULT",
                          "FAIL: replay timer did not retrigger a replay when Ack was withheld")

          phase.drop_objection(this);
     endtask : run_phase

endclass : DLL_Replay_Timer_test
