class mac_rx_driver extends uvm_driver #(Sequence_item);
  `uvm_component_utils(mac_rx_driver)

  virtual pipe_rx_interface vif;
  uvm_analysis_imp #(Sequence_item, mac_rx_driver) item_imp;

  function new(string name, uvm_component parent);
    super.new(name,parent);
    item_imp = new("item_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "","pipe_vif",vif))
      `uvm_fatal("NO_VIF","pipe_rx_interface not set")
  endfunction

      function void write(Sequence_item t);
   //  `uvm_info("PIPE_DRV",$sformatf("Received item from monitor: %0h", t.data),UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
     super.run_phase(phase);
    
    forever begin
      seq_item_port.get_next_item(req);
      // 
      seq_item_port.item_done(req);
    end
  endtask
endclass