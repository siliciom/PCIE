class pma_tx_monitor extends uvm_monitor;
  `uvm_component_utils(pma_tx_monitor)

	virtual phy_tx_interface pvif;
  	virtual pipe_tx_interface pipe_vif;
    uvm_analysis_port #(Sequence_item) pma_tx_port;
    Sequence_item pma_tx_item;
 
  function new (string name = "pma_tx_monitor",uvm_component parent);
	   super.new(name, parent);
	endfunction
 


	function void build_phase(uvm_phase phase);
	   super.build_phase(phase);
      
      pma_tx_port = new ("pma_tx_port", this);
      
      pma_tx_item = Sequence_item::type_id::create("pma_tx_item", this);
      
      if(! uvm_config_db #(virtual phy_tx_interface):: get (this, "", "phy_vif",pvif)) 
	      `uvm_fatal("NO_VIF" ,{"virtual interface must be set for:",get_full_name(),".vif"});
       
      if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "","pipe_vif",pipe_vif))
		 `uvm_fatal("NO_VIF" ,{"virtual interface must be set for:",get_full_name(),".vif"});
	endfunction
  


	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
		 pma_tx_port.write(pma_tx_item);
	endtask

	
		
endclass
