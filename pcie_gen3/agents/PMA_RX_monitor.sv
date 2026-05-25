class pma_rx_monitor extends uvm_monitor;
  `uvm_component_utils(pma_rx_monitor)
  
  
	virtual phy_rx_interface pvif;
  	virtual pipe_rx_interface pipe_vif;
  uvm_analysis_port #(Sequence_item) pma_rx_port;
    Sequence_item pma_rx_item;
 
  function new (string name = "pma_rx_monitor",uvm_component parent);
	   super.new(name, parent);
	endfunction
 


	function void build_phase(uvm_phase phase);
	   super.build_phase(phase);
      pma_rx_port = new ("pma_rx_port", this);
      
      pma_rx_item = Sequence_item::type_id::create("pma_rx_item", this);
      
      if(! uvm_config_db #(virtual phy_rx_interface):: get (this, "", "phy_vif",pvif)) 
	      `uvm_fatal("NO_VIF" ,{"virtual interface must be set for:",get_full_name(),".vif"});
       
      if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "","pipe_vif",pipe_vif))
		 `uvm_fatal("NO_VIF" ,{"virtual interface must be set for:",get_full_name(),".vif"});
	endfunction
  


	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
      pma_rx_port.write(pma_rx_item);
	endtask

	
		
endclass
