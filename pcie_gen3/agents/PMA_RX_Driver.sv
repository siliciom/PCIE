class pma_rx_driver extends uvm_driver#(Sequence_item);
  `uvm_component_utils(pma_rx_driver)

  function new (string name = "pma_rx_driver", uvm_component parent);
		super.new(name,parent);
	endfunction
	
	virtual phy_rx_interface phy_vif;
  uvm_analysis_imp#(Sequence_item, pma_rx_driver) pma_rx_recv;

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
      pma_rx_recv = new ("pma_rx_recv", this);
      if(!uvm_config_db#(virtual phy_rx_interface)::get(this, "","phy_vif",phy_vif))
		 `uvm_fatal("NO_VIF" ,{"virtual interface must be set for:",get_full_name(),".vif"});
	endfunction
  
  
         function void write(Sequence_item pma_tx);
  
          endfunction

	virtual task run_phase(uvm_phase phase);
		
      
	endtask
  
endclass