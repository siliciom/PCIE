//=====================================================================
// Block_Sequences.sv
//
//   Small sequences used by the individual-block tests
//   (tests/Block_TL_Tests.sv, tests/Block_DLL_Tests.sv).
//   See docs/BLOCK_TESTPLAN_ANALYSIS.md.
//=====================================================================

// Send one caller-supplied, already-randomized Sequence_item on the
// TL sequencer. The TL driver's rc_feeder() packs it (pack_tlp) and
// pushes it through the VC arbiter, so nothing is packed here.
class pcie_tl_item_seq extends uvm_sequence #(Sequence_item);
  `uvm_object_utils(pcie_tl_item_seq)
  function new(string name = "pcie_tl_item_seq"); super.new(name); endfunction

  Sequence_item item;    // set by the test before start()

  task body();
    if (item == null) `uvm_fatal("BLK_SEQ", "pcie_tl_item_seq.item is null")
    start_item(item);
    `uvm_info("BLK_SEQ", $sformatf("TL send -> %s", item.convert2string()), UVM_LOW)
    finish_item(item);
  endtask
endclass

// Send a burst of caller-supplied items back to back on the TL
// sequencer (for B2B / arbitration / multi-tag tests).
class pcie_tl_burst_seq extends uvm_sequence #(Sequence_item);
  `uvm_object_utils(pcie_tl_burst_seq)
  function new(string name = "pcie_tl_burst_seq"); super.new(name); endfunction

  Sequence_item items[$];   // set by the test before start()

  task body();
    foreach (items[i]) begin
      start_item(items[i]);
      `uvm_info("BLK_SEQ", $sformatf("TL burst[%0d] -> %s", i, items[i].convert2string()), UVM_LOW)
      finish_item(items[i]);
    end
  endtask
endclass
