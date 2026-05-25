class pma_tx_driver extends uvm_driver#(Sequence_item);
  `uvm_component_utils(pma_tx_driver)

  function new (string name = "pma_tx_driver", uvm_component parent);
		super.new(name,parent);
	endfunction
	
	virtual phy_tx_interface phy_vif;
    uvm_analysis_imp#(Sequence_item, pma_tx_driver) pma_tx_recv;

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
      pma_tx_recv = new ("pma_tx_recv", this);

      if(!uvm_config_db#(virtual phy_tx_interface)::get(this, "","phy_vif",phy_vif))
		 `uvm_fatal("NO_VIF" ,{"virtual interface must be set for:",get_full_name(),".vif"});
	endfunction
  
         function void write(Sequence_item pma_tx);
  
          endfunction

	virtual task run_phase(uvm_phase phase);
		
      
	endtask
  
endclass