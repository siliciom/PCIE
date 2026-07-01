`uvm_analysis_imp_decl(_tr)
`uvm_analysis_imp_decl(_rr)

class TL_Scoreboard extends uvm_component;

  `uvm_component_utils(TL_Scoreboard)

  uvm_analysis_imp_tr #(Sequence_item, TL_Scoreboard) TX_TL_Recv;
  uvm_analysis_imp_rr #(Sequence_item, TL_Scoreboard) RX_TL_Recv;
  uvm_analysis_port #(Sequence_item) t_port;
  uvm_analysis_port #(Sequence_item) r_port;

  Sequence_item tx_req_q[$];
  Sequence_item tx_cpl_q[$];
  Sequence_item rx_req_q[$];
  Sequence_item rx_cpl_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    TX_TL_Recv = new("TX_TL_Recv", this);
    RX_TL_Recv = new("RX_TL_Recv", this);
    t_port    = new("t_port",    this);
    r_port    = new("r_port",    this);
  endfunction

 
  function automatic bit is_completion(Sequence_item pkt);
    return (pkt.e_type == CPL || pkt.e_type == CPL_DATA);
  endfunction

  
  function void write_tr(Sequence_item tx_pkt);

    if (is_completion(tx_pkt)) begin
      tx_cpl_q.push_back(tx_pkt);
      `uvm_info("WRITE_TX_TL_Scoreboard",
                $sformatf("write_tr CPL — tx_cpl_q size=%0d  fmt=%0b r_type=%0b lower_addr=%0b length=%0d e_type=%s",
          tx_cpl_q.size(),
          tx_pkt.fmt,
          tx_pkt.r_type,
          tx_pkt.lower_addr,        
          tx_pkt.length,
          tx_pkt.e_type.name()), UVM_LOW)

      foreach (tx_pkt.payload[j])
        `uvm_info("WRITE_TX_TL_Scoreboard",
          $sformatf("  tx_cpl payload[%0d] = %0h", j, tx_pkt.payload[j]), UVM_LOW)

    end else begin
      tx_req_q.push_back(tx_pkt);
      `uvm_info("WRITE_TX_TL_Scoreboard",
        $sformatf("write_tr REQ — tx_req_q size=%0d  fmt=%0b r_type=%0b addr=%0h length=%0d e_type=%s",
          tx_req_q.size(),
          tx_pkt.fmt,
          tx_pkt.r_type,
          tx_pkt.addr,
          tx_pkt.length,
          tx_pkt.e_type.name()), UVM_LOW)

      foreach (tx_pkt.payload[j])
        `uvm_info("WRITE_TX_TL_Scoreboard",
          $sformatf("  tx_req payload[%0d] = %0h", j, tx_pkt.payload[j]), UVM_LOW)
    end

  endfunction

  
  function void write_rr(Sequence_item rx_pkt);

    if (is_completion(rx_pkt)) begin
      rx_cpl_q.push_back(rx_pkt);
      `uvm_info("WRITE_RX_TL_Scoreboard",
                $sformatf("write_rr CPL — rx_cpl_q size=%0d  fmt=%0b r_type=%0b lower_addr=%0b  length=%0d e_type=%s",
          rx_cpl_q.size(),
          rx_pkt.fmt,
          rx_pkt.r_type,
          rx_pkt.lower_addr,
          rx_pkt.length,
          rx_pkt.e_type.name()), UVM_LOW)

      foreach (rx_pkt.payload[j])
        `uvm_info("WRITE_RX_TL_Scoreboard",
          $sformatf("  rx_cpl payload[%0d] = %0h", j, rx_pkt.payload[j]), UVM_LOW)

    end else begin
      rx_req_q.push_back(rx_pkt);
      `uvm_info("WRITE_RX_TL_Scoreboard",
        $sformatf("write_rr REQ — rx_req_q size=%0d  fmt=%0b r_type=%0b addr=%0h length=%0d e_type=%s",
          rx_req_q.size(),
          rx_pkt.fmt,
          rx_pkt.r_type,
          rx_pkt.addr,
          rx_pkt.length,
          rx_pkt.e_type.name()), UVM_LOW)

      foreach (rx_pkt.payload[j])
        `uvm_info("WRITE_RX_TL_Scoreboard",
          $sformatf("  rx_req payload[%0d] = %0h", j, rx_pkt.payload[j]), UVM_LOW)
    end

  endfunction

  task run_phase(uvm_phase phase);
    fork
      forward_requests();
      forward_completions();
    join
  endtask

  
  task forward_requests();
    Sequence_item tx_pkt, rx_pkt;
    `uvm_info("SB", "Waiting for REQ packets", UVM_LOW)
    forever begin
	    `uvm_info("SB",$sformatf( "Waiting for REQ packets tx = %d, rx = %d",tx_req_q.size(),rx_req_q.size()), UVM_LOW)
      wait (tx_req_q.size() > 0 && rx_req_q.size() > 0);
      tx_pkt = tx_req_q.pop_front();
      rx_pkt = rx_req_q.pop_front();

      `uvm_info("TL_Scoreboard_REQ",
        $sformatf("TX REQ: fmt=%0b r_type=%0b addr=%0h length=%0d e_type=%s payload[0]=%0h",
          tx_pkt.fmt, tx_pkt.r_type, tx_pkt.addr,
          tx_pkt.length, tx_pkt.e_type.name(),
          (tx_pkt.payload.size() > 0) ? tx_pkt.payload[0] : 0), UVM_LOW)

      `uvm_info("TL_Scoreboard_REQ",
        $sformatf("RX REQ: fmt=%0b r_type=%0b addr=%0h length=%0d e_type=%s payload[0]=%0h",
          rx_pkt.fmt, rx_pkt.r_type, rx_pkt.addr,
          rx_pkt.length, rx_pkt.e_type.name(),
          (rx_pkt.payload.size() > 0) ? rx_pkt.payload[0] : 0), UVM_LOW)

      t_port.write(tx_pkt);
      r_port.write(rx_pkt);
    end
  endtask

  
  task forward_completions();
    Sequence_item tx_pkt, rx_pkt;
    forever begin
      wait (tx_cpl_q.size() > 0 && rx_cpl_q.size() > 0);
      tx_pkt = tx_cpl_q.pop_front();
      rx_pkt = rx_cpl_q.pop_front();

      `uvm_info("TL_Scoreboard_CPL",
                $sformatf("TX CPL: fmt=%0b r_type=%0b lower_addr=%0h length=%0d e_type=%s payload[0]=%0h",
          tx_pkt.fmt, tx_pkt.r_type, tx_pkt.lower_addr,
          tx_pkt.length, tx_pkt.e_type.name(),
          (tx_pkt.payload.size() > 0) ? tx_pkt.payload[0] : 0), UVM_LOW)

      `uvm_info("TL_Scoreboard_CPL",
                $sformatf("RX CPL: fmt=%0b r_type=%0b lower_addr=%0h length=%0d e_type=%s payload[0]=%0h",
          rx_pkt.fmt, rx_pkt.r_type, rx_pkt.lower_addr,
          rx_pkt.length, rx_pkt.e_type.name(),
          (rx_pkt.payload.size() > 0) ? rx_pkt.payload[0] : 0), UVM_LOW)

      t_port.write(tx_pkt);
      r_port.write(rx_pkt);
    end
  endtask

endclass


