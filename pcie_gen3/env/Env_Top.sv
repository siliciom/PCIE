class Env_Top extends uvm_env;

  `uvm_component_utils(Env_Top)

  function new(string name = "Env_Top", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  Scoreboard_Top Top_Scb;
  TL_Scoreboard  TL_Scb;
  TX_Env         env_tx;
  RX_Env         env_rx;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env_tx  = TX_Env::type_id::create("env_tx", this);
    env_rx  = RX_Env::type_id::create("env_rx", this);
    Top_Scb = Scoreboard_Top::type_id::create("Top_Scb", this);
    TL_Scb  = TL_Scoreboard::type_id::create("TL_Scb", this);
    

  endfunction : build_phase
  
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env_tx.TX_TL_Agnt.TX_TL_Mon.TX_TL_Send.connect(TL_Scb.TX_TL_Recv);
    env_rx.RX_TL_Agnt.RX_TL_Mon.RX_TL_Send.connect(TL_Scb.RX_TL_Recv);
    TL_Scb.TL_Scb_Send.connect(Top_Scb.TL_Scb_Recv);
  endfunction : connect_phase

endclass : Env_Top