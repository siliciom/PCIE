class apb_slv_sequencer extends uvm_sequencer #(apb_slv_xtn);
     `uvm_component_utils(apb_slv_sequencer)


     function new(string name = "apb_slv_sequencer", uvm_component parent = null);
          super.new(name, parent);
     endfunction


endclass
