class PCIe_PMA_sequencer extends uvm_sequencer #(Sequence_item);
     `uvm_component_utils(PCIe_PMA_sequencer)


     function new(string name = "PCIe_PMA_sequencer", uvm_component parent = null);
          super.new(name, parent);
     endfunction


endclass
