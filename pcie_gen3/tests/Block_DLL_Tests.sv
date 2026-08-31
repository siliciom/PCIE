//=====================================================================
// Block_DLL_Tests.sv  -  individual Data-Link-Layer block tests
//
//   From the Tracker "Testplan" sheet (DLL rows 30/32/34/36/37/38/
//   39/40/43/44) + additions.  See docs/BLOCK_TESTPLAN_ANALYSIS.md.
//
//   Stimulus is injected as a BARE TLP at the DLL sequencer
//   (cfg.stim_layer = STIM_DLL, via layer_base_test) OR, for the
//   error-mechanism tests, as a normal TL write with cfg.inject_err
//   armed on the RC/EP DLL driver.
//
//   Each test checks what the DLL layer itself produced - sequence
//   number, LCRC, ACK-driven replay-buffer retirement, NAK + replay,
//   InitFC / UpdateFC DLLPs - on top of the always-on DL_Scoreboard.
//
//   NOTE: compile-verified only; run-verification pending a Questa
//   sim license (a regression is holding all licenses, 2026-08-31).
//=====================================================================

// Snoops the RC DLL monitor's scoreboard ports:
//   rc_tx      -> framed TLP on the wire : tx_data_sb = [seq, hdr0,
//                 hdr1.., payload.., ecrc, lcrc]
//   rc_dllp_rx -> DLLP the RC received from the EP : rc_dllp_data_sb
//                 = [header0, header1(crc)]
`uvm_analysis_imp_decl(_bdll_tlp)
`uvm_analysis_imp_decl(_bdll_dllp)

class pcie_dll_wire_capture extends uvm_component;
  `uvm_component_utils(pcie_dll_wire_capture)

  uvm_analysis_imp_bdll_tlp  #(Sequence_item, pcie_dll_wire_capture) tlp_tx;
  uvm_analysis_imp_bdll_dllp #(Sequence_item, pcie_dll_wire_capture) dllp_rx;

  // framed TLPs seen on rc_tx
  bit [12:0] tlp_seq[$];
  bit [31:0] tlp_lcrc[$];
  bit [31:0] tlp_body[$][$];    // [seq .. ecrc] (everything except the trailing lcrc)

  // DLLPs the RC received, decoded here from the raw header DW
  int n_ack, n_nak, n_initfc1, n_initfc2, n_updfc, n_fc_any;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    tlp_tx  = new("tlp_tx",  this);
    dllp_rx = new("dllp_rx", this);
  endfunction

  function void write_bdll_tlp(Sequence_item t);
    bit [31:0] q[$] = t.tx_data_sb;
    bit [31:0] body[$];
    if (q.size() < 3) return;
    tlp_seq.push_back(q[0][12:0]);
    tlp_lcrc.push_back(q[q.size()-1]);
    for (int i = 0; i < q.size()-1; i++) body.push_back(q[i]);
    tlp_body.push_back(body);
  endfunction

  function void write_bdll_dllp(Sequence_item t);
    bit [31:0] h0;
    bit [3:0]  fc_t;
    if (t.rc_dllp_data_sb.size() < 1) return;
    h0   = t.rc_dllp_data_sb[0];
    fc_t = h0[7:4];
    // Ack / Nak : type byte in [31:24], reserved [23:13] == 0
    if (h0[31:24] == 8'h00 && h0[23:13] == 0) n_ack++;
    else if (h0[31:24] == 8'h10 && h0[23:13] == 0) n_nak++;
    // FC DLLPs : 4-bit type in [7:4] (create_dllp layout)
    else if (fc_t inside {4'b0100, 4'b0101, 4'b0110}) begin n_initfc1++; n_fc_any++; end
    else if (fc_t inside {4'b1100, 4'b1101, 4'b1110}) begin n_initfc2++; n_fc_any++; end
    else if (fc_t inside {4'b1000, 4'b1001, 4'b1010}) begin n_updfc++;   n_fc_any++; end
  endfunction

  function void clear();
    tlp_seq.delete(); tlp_lcrc.delete(); tlp_body.delete();
    n_ack = 0; n_nak = 0; n_initfc1 = 0; n_initfc2 = 0; n_updfc = 0; n_fc_any = 0;
  endfunction
endclass


//---------------------------------------------------------------------
// base : STIM_DLL injection, link up + enumerated, RC side
//---------------------------------------------------------------------
class block_dll_base_test extends layer_base_test;
  `uvm_component_utils(block_dll_base_test)

  pcie_dll_wire_capture cap;
  int unsigned chk_pass, chk_fail;

  function new(string name = "block_dll_base_test", uvm_component parent = null);
    super.new(name, parent);
    stim_layer   = STIM_DLL;
    wait_link_up = 1;
    do_enum      = 1;
    inject_on_ep = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cap = pcie_dll_wire_capture::type_id::create("cap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Mon.rc_tx.connect(cap.tlp_tx);
    RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Mon.rc_dllp_rx.connect(cap.dllp_rx);
  endfunction

  function void chk(bit cond, string what);
    if (cond) begin chk_pass++; `uvm_info("BLK_CHK", $sformatf("PASS: %s", what), UVM_LOW) end
    else      begin chk_fail++; `uvm_error("BLK_CHK", $sformatf("FAIL: %s", what)) end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (chk_pass == 0 && chk_fail == 0)
      `uvm_error("BLK_CHK", $sformatf("%s ran no checks", get_type_name()))
    `uvm_info("BLK_CHK",
      $sformatf("\n==== %s DLL block checks: pass=%0d fail=%0d ====",
                get_type_name(), chk_pass, chk_fail), UVM_NONE)
  endfunction

  // inject one bare MEM_WR TLP (no seq / no LCRC) at the DLL sequencer
  task inject_memwr(bit [63:0] a, int n = 4, bit [31:0] seed = 32'hD11D_0000);
    pcie_dll_base_seq s;
    Sequence_item     it;
    s  = pcie_dll_base_seq::type_id::create("s");
    it = Sequence_item::type_id::create("it");
    if (!it.randomize() with {
          e_type == MEM_WR; e_fmt == FMT_3DW_DATA;
          addr == a; length == n; payload.size() == n;
          td == 1; tc == 0; tag == 0; first_BE == 4'hF; last_BE == 4'hF;
        })
      `uvm_fatal("BLK", "block DLL inject randomize failed")
    foreach (it.payload[i]) it.payload[i] = seed + i;
    s.tlp = it;
    s.start(dll_seqr());
  endtask

  // recompute the PCIe LCRC over a captured framed body [seq .. ecrc]
  function bit [31:0] golden_lcrc(bit [31:0] body[$]);
    Sequence_item g = Sequence_item::type_id::create("g");
    return g.calculate_lcrc(body);
  endfunction
endclass


//=====================================================================
// Row 43 : DL_Up_State_Test
//=====================================================================
class DL_Up_State_Test extends block_dll_base_test;
  `uvm_component_utils(DL_Up_State_Test)
  function new(string name = "DL_Up_State_Test", uvm_component parent = null);
    super.new(name, parent); endfunction

  task body(uvm_phase phase);
    // layer_base_test::run_phase already blocked on DL_ACTIVE both sides
    chk(RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.rc_dl_up === 1'b1, "RC DLCMSM DL_Up (rc_dl_up=1)");
    chk(EP_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.ep_dl_up === 1'b1, "EP DLCMSM DL_Up (ep_dl_up=1)");
    chk(RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.rc_dl_state ===
        PCIe_DLL_Driver::DL_ACTIVE, "RC DLCMSM state == DL_ACTIVE");
    #20000;
  endtask
endclass


//=====================================================================
// Row 32 : Sequence_Number_Increment_Test
//   inject 4 bare TLPs; DLL stamps consecutive TX sequence numbers
//=====================================================================
class Sequence_Number_Increment_Test extends block_dll_base_test;
  `uvm_component_utils(Sequence_Number_Increment_Test)
  function new(string name = "Sequence_Number_Increment_Test", uvm_component parent = null);
    super.new(name, parent); endfunction

  task body(uvm_phase phase);
    bit [11:0] seq_before;
    int        base;
    seq_before = RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.rc_next_transmit_seq;
    cap.clear();
    for (int i = 0; i < 4; i++) begin
      inject_memwr(bar_base[0] + 64'h200 + i*32, 4, 32'h5EED_0000 + i*32'h100);
      #40000;
    end
    #80000;
    chk(cap.tlp_seq.size() >= 4,
        $sformatf("captured >= 4 framed TLPs on the wire (got %0d)", cap.tlp_seq.size()));
    if (cap.tlp_seq.size() >= 4) begin
      base = cap.tlp_seq[cap.tlp_seq.size()-4];
      for (int i = 1; i < 4; i++)
        chk(cap.tlp_seq[cap.tlp_seq.size()-4+i] == ((base + i) % 4096),
            $sformatf("wire seq[%0d] == base+%0d (base=%0d got=%0d)",
                      i, i, base, cap.tlp_seq[cap.tlp_seq.size()-4+i]));
    end
    chk(((RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.rc_next_transmit_seq - seq_before + 4096) % 4096) >= 4,
        "rc_next_transmit_seq advanced by >= 4");
  endtask
endclass


//=====================================================================
// Row 36 : LCRC_Generation_Test
//   inject 1 bare TLP; DLL appends a correct 32-bit LCRC
//=====================================================================
class LCRC_Generation_Test extends block_dll_base_test;
  `uvm_component_utils(LCRC_Generation_Test)
  function new(string name = "LCRC_Generation_Test", uvm_component parent = null);
    super.new(name, parent); endfunction

  task body(uvm_phase phase);
    bit [31:0] exp;
    cap.clear();
    inject_memwr(bar_base[0] + 64'h300, 4, 32'h1C2C_0000);
    #150000;
    chk(cap.tlp_lcrc.size() >= 1, "captured a framed TLP with a trailing LCRC");
    if (cap.tlp_lcrc.size() >= 1) begin
      exp = golden_lcrc(cap.tlp_body[cap.tlp_body.size()-1]);
      chk(cap.tlp_lcrc[cap.tlp_lcrc.size()-1] === exp,
          $sformatf("LCRC on wire (%08h) == golden recompute over [seq..ecrc] (%08h)",
                    cap.tlp_lcrc[cap.tlp_lcrc.size()-1], exp));
    end
  endtask
endclass


//=====================================================================
// Row 30 : DLLP_ACK_Generation_Test
//   inject a TLP; the EP ACKs it; the RC retires it from the replay
//   buffer -> rc_outstanding_pkt_count returns to 0
//=====================================================================
class DLLP_ACK_Generation_Test extends block_dll_base_test;
  `uvm_component_utils(DLLP_ACK_Generation_Test)
  function new(string name = "DLLP_ACK_Generation_Test", uvm_component parent = null);
    super.new(name, parent); endfunction

  task body(uvm_phase phase);
    int  ack_before;
    bit  saw_outstanding = 0;
    cap.clear();
    ack_before = cap.n_ack;
    inject_memwr(bar_base[0] + 64'h400, 4, 32'hACAC_0000);
    // watch the replay buffer fill then drain
    repeat (200) begin
      #2000;
      if (RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.rc_outstanding_pkt_count > 0)
        saw_outstanding = 1;
    end
    chk(saw_outstanding, "TLP entered the RC replay buffer (rc_outstanding_pkt_count > 0)");
    chk(RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.rc_outstanding_pkt_count == 0,
        "replay buffer drained after ACK (rc_outstanding_pkt_count back to 0)");
    chk(cap.n_ack > ack_before,
        $sformatf("an ACK DLLP was decoded on rc_dllp_rx (before=%0d after=%0d)",
                  ack_before, cap.n_ack));
  endtask
endclass


//=====================================================================
// Rows 38/39/40 : InitFC1 / InitFC2 / UpdateFC DLLP exchange
//   FC1->FC2->DL_ACTIVE only completes if the InitFC handshake ran;
//   UpdateFC DLLPs then flow during steady state
//=====================================================================
class InitFC_DLLP_Exchange_Test extends block_dll_base_test;
  `uvm_component_utils(InitFC_DLLP_Exchange_Test)
  function new(string name = "InitFC_DLLP_Exchange_Test", uvm_component parent = null);
    super.new(name, parent);
    do_enum = 0;   // link bring-up is enough
  endfunction

  task body(uvm_phase phase);
    // cap has been recording since connect_phase, i.e. through link init
    chk(RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.rc_dl_up === 1'b1 &&
        EP_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.ep_dl_up === 1'b1,
        "both DLCMSMs reached DL_Up (InitFC1->InitFC2->DL_ACTIVE completed)");
    chk(cap.n_fc_any >= 1,
        $sformatf("at least one FC DLLP was decoded on rc_dllp_rx (fc1=%0d fc2=%0d upd=%0d)",
                  cap.n_initfc1, cap.n_initfc2, cap.n_updfc));
    // drive some credit-consuming traffic and look for UpdateFC
    for (int i = 0; i < 3; i++) begin
      inject_memwr(64'h1000 + i*64'h40, 8, 32'hFC00_0000 + i);
      #60000;
    end
    #150000;
    chk(cap.n_updfc >= 1,
        $sformatf("UpdateFC DLLP(s) seen after credit-consuming traffic (n=%0d)", cap.n_updfc));
  endtask
endclass


//=====================================================================
// Rows 34/37 : LCRC error -> NAK -> replay
//   normal TL write, ERR_LCRC armed on the RC DLL driver (one-shot).
//   The RX DLL monitor flags "LCRC MISMATCH"; the RC replays the
//   packet from its buffer (replay_num increments).
//=====================================================================
class DLLP_NAK_And_Replay_Test extends block_dll_base_test;
  `uvm_component_utils(DLLP_NAK_And_Replay_Test)
  Single_Mem_Wr_Rd_3DW   mem_seq;
  Error_Report_Catcher   catcher;

  function new(string name = "DLLP_NAK_And_Replay_Test", uvm_component parent = null);
    super.new(name, parent);
    stim_layer = STIM_TL;   // use the normal path so the RC DLL frames + we corrupt its LCRC
    do_enum    = 1;
  endfunction

  task body(uvm_phase phase);
    bit saw_replay = 0;
    catcher = Error_Report_Catcher::get();
    catcher.reset();
    catcher.arm("RX_DLL_MON", "LCRC MISMATCH");

    RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.replay_en  = 1'b1;
    RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err = ERR_LCRC;

    mem_seq = Single_Mem_Wr_Rd_3DW::type_id::create("mem_seq");
    mem_seq.p_wr_fmt = bar_wr_fmt[0];
    mem_seq.p_rd_fmt = bar_rd_fmt[0];
    mem_seq.p_addr   = bar_base[0] + 64'h600;
    mem_seq.p_length = 4;
    mem_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

    #300000;

    foreach (RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.rc_replay_buffer[k])
      if (RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.rc_replay_buffer[k].replay_num > 0)
        saw_replay = 1;

    chk(catcher.hit_cnt > 0, "corrupted LCRC detected by the RX DLL monitor (NAK path)");
    chk(saw_replay || cap.n_nak > 0,
        "RC retransmitted from the replay buffer (replay_num>0) or a NAK DLLP was decoded");

    RC_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err = ERR_NONE;
  endtask
endclass


//=====================================================================
// Row 44 : Bad DLLP (DLLP CRC error) -> Bad-DLLP handling
//   ERR_DLLP_CRC armed on the EP DLL driver corrupts the EP's Ack
//   DLLP CRC; the RC's TX DLL monitor flags it.
//=====================================================================
class DLLP_CRC_Error_Test extends block_dll_base_test;
  `uvm_component_utils(DLLP_CRC_Error_Test)
  Single_Mem_Wr_Rd_3DW   mem_seq;
  Error_Report_Catcher   catcher;

  function new(string name = "DLLP_CRC_Error_Test", uvm_component parent = null);
    super.new(name, parent);
    stim_layer = STIM_TL;
    do_enum    = 1;
  endfunction

  task body(uvm_phase phase);
    catcher = Error_Report_Catcher::get();
    catcher.reset();
    catcher.arm("TX_DLL_MON", "CRC");

    EP_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err = ERR_DLLP_CRC;

    mem_seq = Single_Mem_Wr_Rd_3DW::type_id::create("mem_seq");
    mem_seq.p_wr_fmt = bar_wr_fmt[0];
    mem_seq.p_rd_fmt = bar_rd_fmt[0];
    mem_seq.p_addr   = bar_base[0] + 64'h700;
    mem_seq.p_length = 4;
    mem_seq.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);

    #300000;

    chk(catcher.hit_cnt > 0, "corrupted DLLP CRC detected (Bad-DLLP path)");

    EP_Env[0].PCIe_DLL_Agnt.PCIe_DLL_Drv.cfg.inject_err = ERR_NONE;
  endtask
endclass
