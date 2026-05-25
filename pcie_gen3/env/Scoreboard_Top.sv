class Scoreboard_Top extends uvm_scoreboard;

  `uvm_component_utils(Scoreboard_Top)

  uvm_analysis_imp #(Sequence_item, Scoreboard_Top) TL_Scb_Recv;

  function new(string name = "Scoreboard_Top", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    TL_Scb_Recv = new("TL_Scb_Recv", this);

  endfunction : build_phase

  function void write(Sequence_item t_x);

  endfunction : write

endclass : Scoreboard_Top