//=====================================================================
// Layer_Sequences.sv
//
//   Base sequences for layered stimulus (see docs/LAYERED_STIMULUS_PLAN.md).
//   Each targets the matching layer sequencer:
//     pcie_dll_base_seq  ->  RC_Env[i].PCIe_DLL_Agnt.PCIe_DLL_Seqr   (or EP_Env)
//     pcie_mac_base_seq  ->  RC_Env[i].TX_MAC_Agnt.seqr
//     pcie_pma_base_seq  ->  RC_Env[i].TX_PMA_Agnt.PCIe_PMA_seqr
//   and requires the matching env_cfg.stim_layer to be set on that side.
//
//   Usage from a test:
//     s = pcie_dll_base_seq::type_id::create("s");
//     s.tlp = <a randomized Sequence_item>;     // or s.raw_dw = '{...}
//     s.start( dll_seqr() );                    // runs s.body()
//=====================================================================

//---------------------------------------------------------------------
// DLL layer : inject a bare TLP (the DLL driver adds seq # + LCRC),
// or an arbitrary DW list.
//---------------------------------------------------------------------
class pcie_dll_base_seq extends uvm_sequence #(Sequence_item);
  `uvm_object_utils(pcie_dll_base_seq)
  function new(string name = "pcie_dll_base_seq"); super.new(name); endfunction

  // Set exactly one of these on the sequence before start():
  Sequence_item tlp;         // a randomized TLP - packed into a bare DW stream
  bit [31:0]    raw_dw[$];   // an arbitrary DW list, injected as-is

  task body();
    Sequence_item req;
    if (tlp != null) begin
      req = tlp;
      start_item(req);
      req.build_dll_stream();
      `uvm_info("DLL_SEQ", $sformatf("inject TLP -> %s (%0d DW, no seq/LCRC)",
               req.convert2string(), req.tx_data_t.size()), UVM_LOW)
      finish_item(req);
    end
    else begin
      req = Sequence_item::type_id::create("dll_raw");
      start_item(req);
      req.stamp_uid();
      req.tx_data_t.delete();  req.tx_data.delete();
      foreach (raw_dw[i]) begin req.tx_data_t.push_back(raw_dw[i]); req.tx_data.push_back(raw_dw[i]); end
      `uvm_info("DLL_SEQ", $sformatf("inject RAW [uid=%0d] %0d DW", req.pkt_uid, raw_dw.size()), UVM_LOW)
      finish_item(req);
    end
  endtask
endclass

//---------------------------------------------------------------------
// MAC layer : inject a fully framed DLL packet (seq # + TLP + LCRC).
// The MAC driver adds the STP token and byte-stripes across lanes.
//---------------------------------------------------------------------
class pcie_mac_base_seq extends uvm_sequence #(Sequence_item);
  `uvm_object_utils(pcie_mac_base_seq)
  function new(string name = "pcie_mac_base_seq"); super.new(name); endfunction

  Sequence_item tlp;              // a randomized TLP
  bit [11:0]    seq_no = 12'h1;   // DL sequence number to stamp in

  task body();
    start_item(tlp);
    tlp.build_mac_stream(seq_no);
    `uvm_info("MAC_SEQ", $sformatf("inject framed seq=%0h -> %s (%0d DW incl seq+LCRC)",
             seq_no, tlp.convert2string(), tlp.mac_tx_data[0].size()), UVM_LOW)
    finish_item(tlp);
  endtask
endclass

//---------------------------------------------------------------------
// PMA layer (v1, RC side): inject a DW stream, packed into 130-bit
// data blocks (2'b10 sync header). NOTE: not scrambled - see
// LAYERED_STIMULUS_PLAN.md risks.
//---------------------------------------------------------------------
class pcie_pma_base_seq extends uvm_sequence #(Sequence_item);
  `uvm_object_utils(pcie_pma_base_seq)
  function new(string name = "pcie_pma_base_seq"); super.new(name); endfunction

  bit [31:0] dw_stream[$];
  int        lane = 0;

  task body();
    Sequence_item req;
    req = Sequence_item::type_id::create("pma_stream");
    start_item(req);
    req.stamp_uid();
    req.build_pma_blocks(dw_stream, lane);
    `uvm_info("PMA_SEQ", $sformatf("inject [uid=%0d] %0d DW -> %0d blocks on lane %0d",
             req.pkt_uid, dw_stream.size(), req.pma_tx_data[lane].size(), lane), UVM_LOW)
    finish_item(req);
  endtask
endclass
