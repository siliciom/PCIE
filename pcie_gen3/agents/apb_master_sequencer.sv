class sequencer_apb_master extends uvm_sequencer#(seq_item_apb_master);
	`uvm_component_utils(sequencer_apb_master)

	function new(string name = "sequencer_apb_master",uvm_component parent);
		super.new(name,parent);
	endfunction
endclass : sequencer_apb_master
