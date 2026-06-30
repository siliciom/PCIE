class TL_Scoreboard extends uvm_scoreboard;
  
  `uvm_component_utils(TL_Scoreboard)
  
  uvm_analysis_imp#(Sequence_item, TL_Scoreboard) TX_TL_Recv;
  //uvm_analysis_imp#(Sequence_item, TL_Scoreboard) RX_TL_Recv;

  uvm_analysis_port#(Sequence_item)                    TL_Scb_Send;

  
  function new(string name = "TL_Scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    TX_TL_Recv  = new("TX_TL_Recv", this);
    //RX_TL_Recv  = new("RX_TL_Recv", this);
    TL_Scb_Send = new("TL_Scb_Send", this);
  endfunction : build_phase
  
  function void write(Sequence_item t_x);
    // PCIe Ordering Checker Logic //
  endfunction : write
  
endclass : TL_Scoreboard
