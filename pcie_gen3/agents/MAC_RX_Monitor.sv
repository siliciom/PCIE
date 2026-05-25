class mac_rx_monitor extends uvm_monitor;
  `uvm_component_utils(mac_rx_monitor)

  virtual RX_DLL_PCS_Interface vif;
  virtual pipe_rx_interface pvif;
  uvm_analysis_port #(Sequence_item) item_port;
      Sequence_item item;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    item_port = new("item_port", this);
    item = Sequence_item::type_id::create("item");
    if(!uvm_config_db#(virtual RX_DLL_PCS_Interface)::get(this, "", "DLL_Vif", vif))
      `uvm_fatal("NO_VIF","RX_DLL_PCS_Interface not set (vif missing)")
      if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "","pipe_vif",pvif))
        `uvm_fatal("NO_VIF","pipe_rx_interface not set")
  endfunction

 
	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
        item_port.write(item);
  endtask
endclass