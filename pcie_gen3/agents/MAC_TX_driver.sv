class mac_tx_driver extends uvm_driver #(Sequence_item);
  `uvm_component_utils(mac_tx_driver)

  virtual pipe_tx_interface vif;
  uvm_analysis_imp #(Sequence_item, mac_tx_driver) item_imp;

  bit [31:0] received [$];
  uvm_event pipe_tx;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_imp = new("item_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    pipe_tx = new();

    if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "", "pipe_vif", vif))
      `uvm_fatal("NO_VIF", "pipe_tx_interface not set")
  endfunction

  function void write(Sequence_item t);
    received.push_back(t.data);
    pipe_tx.trigger();
//     `uvm_info("PIPE_DRV",$sformatf("Received item from monitor: %0p",received),UVM_LOW)

  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);

//     vif.TxDataValid <= 0;
//     vif.TxData      <= 0;

    forever begin
      @(posedge vif.CLK);

      if(received.size() > 0) begin
        vif.TxData      <= received.pop_front();
        vif.TxDataValid <= 1;
      end
      else begin
        vif.TxDataValid <= 0;
      end
    end
  endtask

endclass