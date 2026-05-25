class mac_tx_monitor extends uvm_monitor;
  `uvm_component_utils(mac_tx_monitor)

  virtual TX_DLL_PCS_Interface vif;
  virtual pipe_tx_interface pvif;
  uvm_analysis_port #(Sequence_item) item_port;
      Sequence_item item;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    item_port = new("item_port", this);
   
    if(!uvm_config_db#(virtual TX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", vif))
      `uvm_fatal("NO_VIF","TX_DLL_PCS_Interface not set (vif missing)")
      if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "","pipe_vif",pvif))
      `uvm_fatal("NO_VIF","pipe_tx_interface not set")
  endfunction

 
	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
    forever begin
       item = Sequence_item::type_id::create("item");
      @(negedge vif.CLK);

      if (vif.dl_tx_valid && vif.dl_tx_ready) begin
//         $display("time at monitor %t",$time);
        item.data = vif.dl_tx_data;
        item_port.write(item);
      end
    end
  endtask
endclass 
