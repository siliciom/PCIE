//=====================================================================
// Block_TL_Tests.sv  -  individual Transaction-Layer block tests
//
//   From the Tracker "Testplan" sheet (TL rows) + additions.
//   See docs/BLOCK_TESTPLAN_ANALYSIS.md for the per-row analysis.
//
//   These start at the TL sequencer (the normal path) and add a
//   focused check on the EP-received TLP / EP memory / config space,
//   on top of the always-on scoreboards.
//=====================================================================

// Captures every request the EP TL monitor forwards (RX_TL_MON_Send).
class pcie_ep_rx_tlp_capture extends uvm_subscriber #(Sequence_item);
  `uvm_component_utils(pcie_ep_rx_tlp_capture)
  Sequence_item last;
  Sequence_item hist[$];
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void write(Sequence_item t);
    last = t;
    hist.push_back(t);
    `uvm_info("EP_RX_CAP", $sformatf("captured -> %s", t.convert2string()), UVM_MEDIUM)
  endfunction
  function void clear(); hist.delete(); last = null; endfunction
endclass


class block_tl_base_test extends pcie_base_test;
  `uvm_component_utils(block_tl_base_test)

  pcie_ep_rx_tlp_capture ep_cap;
  int unsigned           chk_pass;
  int unsigned           chk_fail;

  function new(string name = "block_tl_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ep_cap = pcie_ep_rx_tlp_capture::type_id::create("ep_cap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // extra subscriber on an existing analysis port - no monitor change
    EP_Env[0].PCIe_TL_Agnt.TX_TL_Mon.RX_TL_MON_Send.connect(ep_cap.analysis_export);
  endfunction

  // ---- tiny check helpers ----
  function void chk(bit cond, string what);
    if (cond) begin chk_pass++;
      `uvm_info("BLK_CHK", $sformatf("PASS: %s", what), UVM_LOW)
    end else begin chk_fail++;
      `uvm_error("BLK_CHK", $sformatf("FAIL: %s", what))
    end
  endfunction

  function void chk_eq(longint unsigned got, longint unsigned exp, string what);
    chk(got === exp, $sformatf("%s (got=%0h exp=%0h)", what, got, exp));
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("BLK_CHK",
      $sformatf("\n==== %s block checks: pass=%0d fail=%0d ====",
                get_type_name(), chk_pass, chk_fail), UVM_NONE)
    if (chk_fail == 0 && chk_pass == 0)
      `uvm_error("BLK_CHK", "no block checks ran - test body did nothing")
  endfunction

  // ---- reusable stimulus ----
  // one MEM write of `len` DW at `addr`, payload = seed, seed+1, ...
  task do_mem_write(bit [63:0] addr, int len, fmt_e wfmt, bit [31:0] seed = 32'hA5A5_0000,
                    bit [3:0] fbe = 4'hF, bit [3:0] lbe = 4'hF, bit set_td = 1);
    pcie_tl_item_seq s;
    Sequence_item    it;
    s  = pcie_tl_item_seq::type_id::create("s");
    it = Sequence_item::type_id::create("it");
    assert(it.randomize() with {
      e_type == MEM_WR; e_fmt == wfmt; local::addr == addr;
      length == local::len; payload.size() == local::len;
      td == local::set_td; tc == 0; tag == 0;
      first_BE == local::fbe; last_BE == local::lbe;
    }) else `uvm_fatal("BLK", "mem_write randomize failed");
    foreach (it.payload[i]) it.payload[i] = seed + i;
    s.item = it;
    s.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
  endtask

  // one MEM read of `len` DW at `addr`; returns the CplD payload.
  task do_mem_read(input bit [63:0] addr, input int len, input fmt_e rfmt,
                   output bit [31:0] rdata[$], input bit set_td = 1);
    pcie_tl_item_seq s;
    Sequence_item    it, cpl;
    int              tg;
    s  = pcie_tl_item_seq::type_id::create("s");
    it = Sequence_item::type_id::create("it");
    tg = RC_Env[0].PCIe_TL_Agnt.tag_mgr.allocate_tag();
    assert(it.randomize() with {
      e_type == MEM_RD; e_fmt == rfmt; local::addr == addr;
      length == local::len; td == local::set_td; tc == 0; tag == local::tg;
    }) else `uvm_fatal("BLK", "mem_read randomize failed");
    s.item = it;
    s.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
    rdata.delete();
    // collect CplD(s) for this tag
    forever begin
      cpl_fifo.get(cpl);
      if (cpl.tag == tg && cpl.e_type == CPL_DATA) begin
        foreach (cpl.payload[i]) rdata.push_back(cpl.payload[i]);
        if (rdata.size() >= len) break;
      end
    end
  endtask

  // EP LUT memory (byte address) helper
  function bit [31:0] ep_mem(bit [63:0] byte_addr);
    return EP_Env[0].PCIe_TL_Agnt.PCIe_LUT.mem_space.exists(byte_addr) ?
           EP_Env[0].PCIe_TL_Agnt.PCIe_LUT.mem_space[byte_addr] : 32'h0;
  endfunction
endclass


//---------------------------------------------------------------------
// Row 2 : PCIe_TL_4DW_MWr_Basic
//---------------------------------------------------------------------
class PCIe_TL_4DW_MWr_Basic extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_4DW_MWr_Basic)
  function new(string name = "PCIe_TL_4DW_MWr_Basic", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    bit [63:0] a;
    super.run_phase(phase);            // link-up + enumeration
    phase.raise_objection(this);
    a = bar_base[1] + 64'h40;          // BAR1 = 64-bit -> 4DW
    ep_cap.clear();
    do_mem_write(a, 8, FMT_4DW_DATA, 32'h1111_0000);
    #100000;
    chk(ep_cap.last != null, "EP received the 4DW MWr");
    if (ep_cap.last != null) begin
      chk_eq(ep_cap.last.fmt,    3'b011, "fmt == 4DW-with-data");
      chk_eq(ep_cap.last.r_type, 5'b00000, "type == MEM");
      chk_eq(ep_cap.last.len_dw(), 8, "length == 8 DW");
      chk_eq(ep_cap.last.addr,   a, "address");
    end
    // memory-model check for a couple of DWs
    chk_eq(ep_mem(a),      32'h1111_0000, "mem[a]");
    chk_eq(ep_mem(a+4*7),  32'h1111_0007, "mem[a+7DW]");
    phase.drop_objection(this);
  endtask
endclass


//---------------------------------------------------------------------
// Row 3 / 4 : PCIe_TL_3DW_MRd_Basic / PCIe_TL_4DW_MRd_Basic
//---------------------------------------------------------------------
class PCIe_TL_3DW_MRd_Basic extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_3DW_MRd_Basic)
  function new(string name = "PCIe_TL_3DW_MRd_Basic", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    bit [63:0] a; bit [31:0] rd[$];
    super.run_phase(phase);
    phase.raise_objection(this);
    a = bar_base[0] + 64'h80;          // BAR0 = 32-bit -> 3DW
    do_mem_write(a, 4, FMT_3DW_DATA, 32'hDEAD_0000);
    #80000;
    do_mem_read(a, 4, FMT_3DW_NO_DATA, rd);
    chk_eq(rd.size(), 4, "CplD returned 4 DW");
    for (int i = 0; i < rd.size(); i++)
      chk_eq(rd[i], 32'hDEAD_0000 + i, $sformatf("read DW[%0d] == written", i));
    phase.drop_objection(this);
  endtask
endclass

class PCIe_TL_4DW_MRd_Basic extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_4DW_MRd_Basic)
  function new(string name = "PCIe_TL_4DW_MRd_Basic", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    bit [63:0] a; bit [31:0] rd[$];
    super.run_phase(phase);
    phase.raise_objection(this);
    a = bar_base[1] + 64'h80;
    do_mem_write(a, 4, FMT_4DW_DATA, 32'hBEEF_0000);
    #80000;
    do_mem_read(a, 4, FMT_4DW_NO_DATA, rd);
    chk_eq(rd.size(), 4, "CplD returned 4 DW");
    for (int i = 0; i < rd.size(); i++)
      chk_eq(rd[i], 32'hBEEF_0000 + i, $sformatf("read DW[%0d] == written", i));
    phase.drop_objection(this);
  endtask
endclass


//---------------------------------------------------------------------
// Row 7 / 8 : CfgWr0 / CfgRd0 field check  (uses base-test cfg tasks)
//---------------------------------------------------------------------
class PCIe_TL_3DW_CfgWr_type0 extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_3DW_CfgWr_type0)
  function new(string name = "PCIe_TL_3DW_CfgWr_type0", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    bit [31:0] rb;
    super.run_phase(phase);
    phase.raise_objection(this);
    // Cache Line Size register (reg 0x0C, byte 0) is RW
    cfg_write(4'h0, 6'hC, 32'h0000_0040, 4'b0001);
    cfg_read (4'h0, 6'hC, rb);
    chk_eq(rb[7:0], 8'h40, "CfgWr0 landed in cfg_mem (cache line size)");
    chk_eq(EP_Env[0].cfg_model.read_reg(10'hC) & 32'hFF, 32'h40, "EP cfg_model updated");
    phase.drop_objection(this);
  endtask
endclass

class PCIe_TL_3DW_CfgRd_type0 extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_3DW_CfgRd_type0)
  function new(string name = "PCIe_TL_3DW_CfgRd_type0", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    bit [31:0] vid;
    super.run_phase(phase);
    phase.raise_objection(this);
    cfg_read(4'h0, 6'h0, vid);
    chk_eq(vid, EP_Env[0].cfg_model.read_reg(10'h0), "CfgRd0 data == EP cfg_model[0]");
    chk(vid[15:0] != 16'hFFFF, "Vendor ID valid");
    phase.drop_objection(this);
  endtask
endclass


//---------------------------------------------------------------------
// Row 12 : PCIe_TL_TLP_Digest_FieldCheck  (TD=1 -> valid ECRC)
//---------------------------------------------------------------------
class PCIe_TL_TLP_Digest_FieldCheck extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_TLP_Digest_FieldCheck)
  function new(string name = "PCIe_TL_TLP_Digest_FieldCheck", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    bit [63:0] a;
    super.run_phase(phase);
    phase.raise_objection(this);
    a = bar_base[0] + 64'hA0;
    ep_cap.clear();
    do_mem_write(a, 4, FMT_3DW_DATA, 32'hEC12_0000, 4'hF, 4'hF, /*td*/1);
    #100000;
    chk(ep_cap.last != null, "EP received the TD=1 MWr");
    if (ep_cap.last != null) begin
      chk_eq(ep_cap.last.td, 1, "TD bit set");
      chk_eq(ep_cap.last.ecrc_error, 0, "ECRC recompute matched (no ecrc_error)");
    end
    // no UVM_ERROR from RX_TL_MONITOR "ECRC MISMATCH" is the real check
    phase.drop_objection(this);
  endtask
endclass


//---------------------------------------------------------------------
// Row 15 : PCIe_TL_Length_1DW_write
//---------------------------------------------------------------------
class PCIe_TL_Length_1DW_write extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_Length_1DW_write)
  function new(string name = "PCIe_TL_Length_1DW_write", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    bit [63:0] a; bit [31:0] rd[$];
    super.run_phase(phase);
    phase.raise_objection(this);
    a = bar_base[0] + 64'hB0;
    ep_cap.clear();
    do_mem_write(a, 1, FMT_3DW_DATA, 32'h0001_2345);
    #80000;
    chk(ep_cap.last != null && ep_cap.last.len_dw() == 1, "1-DW length on the wire");
    chk_eq(ep_mem(a), 32'h0001_2345, "1 DW written to mem");
    do_mem_read(a, 1, FMT_3DW_NO_DATA, rd);
    chk_eq(rd.size(), 1, "1-DW CplD");
    chk_eq(rd[0], 32'h0001_2345, "read back == written");
    phase.drop_objection(this);
  endtask
endclass


//---------------------------------------------------------------------
// Row 20 / 21 / 23 : byte-enable field checks
//---------------------------------------------------------------------
class PCIe_TL_FirstByte_Enable_Full extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_FirstByte_Enable_Full)
  function new(string name = "PCIe_TL_FirstByte_Enable_Full", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    bit [63:0] a;
    super.run_phase(phase);
    phase.raise_objection(this);
    a = bar_base[0] + 64'hC0;
    do_mem_write(a, 1, FMT_3DW_DATA, 32'hFFEE_DDCC, 4'b1111, 4'b0000);
    #80000;
    chk_eq(ep_mem(a), 32'hFFEE_DDCC, "first_BE=1111 -> all 4 bytes written");
    phase.drop_objection(this);
  endtask
endclass

class PCIe_TL_FirstByte_Enable_Partial extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_FirstByte_Enable_Partial)
  function new(string name = "PCIe_TL_FirstByte_Enable_Partial", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    bit [63:0] a; bit [31:0] pre_val;
    super.run_phase(phase);
    phase.raise_objection(this);
    a = bar_base[0] + 64'hD0;
    do_mem_write(a, 1, FMT_3DW_DATA, 32'h0000_0000, 4'b1111, 4'b0000); // preset 0
    #40000;
    pre_val = ep_mem(a);
    do_mem_write(a, 1, FMT_3DW_DATA, 32'hAABB_CCDD, 4'b0011, 4'b0000); // only low 2 bytes
    #60000;
    chk_eq(ep_mem(a)[15:0],  16'hCCDD, "enabled bytes updated");
    chk_eq(ep_mem(a)[31:16], pre_val[31:16], "disabled bytes preserved");
    phase.drop_objection(this);
  endtask
endclass

class PCIe_TL_LastByte_Enable_Valid extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_LastByte_Enable_Valid)
  function new(string name = "PCIe_TL_LastByte_Enable_Valid", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    bit [63:0] a;
    super.run_phase(phase);
    phase.raise_objection(this);
    a = bar_base[0] + 64'hE0;
    do_mem_write(a, 4, FMT_3DW_DATA, 32'h0000_0000, 4'hF, 4'hF); // preset
    #40000;
    do_mem_write(a, 4, FMT_3DW_DATA, 32'h1122_3344, 4'b1111, 4'b0111); // last DW: low 3 bytes
    #80000;
    chk_eq(ep_mem(a+12)[23:0],  24'h223344 + 3, "last DW: enabled 3 bytes updated");
    // (seed+3 low bytes; upper byte of last DW must be unchanged from preset 0)
    chk_eq(ep_mem(a+12)[31:24], 8'h00, "last DW: disabled top byte preserved");
    phase.drop_objection(this);
  endtask
endclass


//---------------------------------------------------------------------
// ADDITION : Attr (RO / NS / IDO) field carried unchanged
//---------------------------------------------------------------------
class PCIe_TL_Attr_FieldCheck extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_Attr_FieldCheck)
  function new(string name = "PCIe_TL_Attr_FieldCheck", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    pcie_tl_item_seq s; Sequence_item it; bit [63:0] a;
    super.run_phase(phase);
    phase.raise_objection(this);
    a = bar_base[0] + 64'hF0;
    ep_cap.clear();
    s  = pcie_tl_item_seq::type_id::create("s");
    it = Sequence_item::type_id::create("it");
    assert(it.randomize() with {
      e_type == MEM_WR; e_fmt == FMT_3DW_DATA; addr == a;
      length == 4; payload.size() == 4; td == 1; tc == 0; tag == 0;
      first_BE == 4'hF; last_BE == 4'hF;
      attr_1 == 1'b1; attr_2 == 2'b11;      // IDO + (RO,NS)
    }) else `uvm_fatal("BLK","randomize");
    foreach (it.payload[i]) it.payload[i] = 32'hA770_0000 + i;
    s.item = it; s.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
    #100000;
    chk(ep_cap.last != null, "EP received the TLP");
    if (ep_cap.last != null) begin
      chk_eq(ep_cap.last.attr_1, 1'b1,   "Attr[2] (IDO) carried");
      chk_eq(ep_cap.last.attr_2, 2'b11,  "Attr[1:0] (RO,NS) carried");
    end
    phase.drop_objection(this);
  endtask
endclass


//---------------------------------------------------------------------
// ADDITION : TC field + TC->VC mapping
//---------------------------------------------------------------------
class PCIe_TL_TC_FieldCheck extends block_tl_base_test;
  `uvm_component_utils(PCIe_TL_TC_FieldCheck)
  function new(string name = "PCIe_TL_TC_FieldCheck", uvm_component parent = null);
    super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    pcie_tl_item_seq s; Sequence_item it; bit [63:0] a;
    super.run_phase(phase);
    phase.raise_objection(this);
    a = bar_base[0] + 64'h100;
    ep_cap.clear();
    s  = pcie_tl_item_seq::type_id::create("s");
    it = Sequence_item::type_id::create("it");
    assert(it.randomize() with {
      e_type == MEM_WR; e_fmt == FMT_3DW_DATA; addr == a;
      length == 2; payload.size() == 2; td == 1; tag == 0;
      first_BE == 4'hF; last_BE == 4'hF;
      tc == 3;
    }) else `uvm_fatal("BLK","randomize");
    it.payload[0] = 32'h7C00_0000; it.payload[1] = 32'h7C00_0001;
    s.item = it; s.start(RC_Env[0].PCIe_TL_Agnt.TX_TL_Seqr);
    #100000;
    chk(ep_cap.last != null, "EP received the TC=3 TLP");
    if (ep_cap.last != null) begin
      chk_eq(ep_cap.last.tc, 3, "TC field carried");
      chk_eq(ep_cap.last.vc, VC3, "TC3 -> VC3 (identity tc2vc map)");
    end
    phase.drop_objection(this);
  endtask
endclass
