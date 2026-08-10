`uvm_analysis_imp_decl(_t)
`uvm_analysis_imp_decl(_r)

class Scoreboard_Top extends uvm_scoreboard;
  `uvm_component_utils(Scoreboard_Top)

  uvm_analysis_imp_t #(Sequence_item, Scoreboard_Top) t_imp;
  uvm_analysis_imp_r #(Sequence_item, Scoreboard_Top) r_imp;

  Sequence_item tx_req_q[$];
  Sequence_item rx_req_q[$];
  Sequence_item tx_cpl_q[$];
  Sequence_item rx_cpl_q[$];

  static int fail_cnt;
  static int pass_cnt;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    fail_cnt = 0;
    pass_cnt = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    t_imp = new("t_imp", this);
    r_imp = new("r_imp", this);
  endfunction

  
  function automatic bit is_completion(Sequence_item pkt);
    return (pkt.e_type == CPL || pkt.e_type == CPL_DATA);
  endfunction

  
  virtual function void write_t(Sequence_item tx_pkt);

    `uvm_info("SCOREBOARD",
      $sformatf("TX packet received from TL monitor: e_type=%s", tx_pkt.e_type.name()),
      UVM_LOW)

    if (is_completion(tx_pkt)) begin
      tx_cpl_q.push_back(tx_pkt);
      `uvm_info("SCOREBOARD",
        $sformatf("write_t: CPL queued, tx_cpl_q size=%0d e_type=%s",
          tx_cpl_q.size(), tx_pkt.e_type.name()), UVM_HIGH)
    end else begin
      tx_req_q.push_back(tx_pkt);
      `uvm_info("SCOREBOARD",
        $sformatf("write_t: REQ queued, tx_req_q size=%0d e_type=%s",
          tx_req_q.size(), tx_pkt.e_type.name()), UVM_HIGH)
    end

  endfunction

 
  virtual function void write_r(Sequence_item rx_pkt);

    `uvm_info("SCOREBOARD",
      $sformatf("RX packet received from TL monitor: e_type=%s", rx_pkt.e_type.name()),
      UVM_LOW)

    if (is_completion(rx_pkt)) begin
      rx_cpl_q.push_back(rx_pkt);
      `uvm_info("SCOREBOARD",
        $sformatf("write_r: CPL queued, rx_cpl_q size=%0d e_type=%s",
          rx_cpl_q.size(), rx_pkt.e_type.name()), UVM_HIGH)
    end else begin
      rx_req_q.push_back(rx_pkt);
      `uvm_info("SCOREBOARD",
        $sformatf("write_r: REQ queued, rx_req_q size=%0d e_type=%s",
          rx_req_q.size(), rx_pkt.e_type.name()), UVM_HIGH)
    end

  endfunction

  
  task run_phase(uvm_phase phase);
    fork
      check_requests();
      check_completions();
    join
  endtask

 
  task check_requests();
    Sequence_item tx_pkt, rx_pkt;
    forever begin
      wait(tx_req_q.size() > 0 && rx_req_q.size() > 0);
      tx_pkt = tx_req_q.pop_front();
      rx_pkt = rx_req_q.pop_front();
      compare_tlp(tx_pkt, rx_pkt, "REQUEST");
    end
  endtask

  
  task check_completions();
    Sequence_item tx_pkt, rx_pkt;
    forever begin
      wait(tx_cpl_q.size() > 0 && rx_cpl_q.size() > 0);
      tx_pkt = tx_cpl_q.pop_front();
      rx_pkt = rx_cpl_q.pop_front();
      compare_tlp(tx_pkt, rx_pkt, "COMPLETION");
    end
  endtask

  
  function void compare_tlp(Sequence_item tx_pkt, Sequence_item rx_pkt,
                             string tlp_kind);

    `uvm_info("SCOREBOARD",
      $sformatf("Comparing %s TLP -- TX e_type=%s (%0d DWs) vs RX e_type=%s (%0d DWs)",
        tlp_kind, tx_pkt.e_type.name(), tx_pkt.tlp_q.size(),
        rx_pkt.e_type.name(), rx_pkt.tlp_q.size()), UVM_LOW)

    if (tx_pkt.tlp_q.size() !== rx_pkt.tlp_q.size()) begin
      `uvm_error("FAIL",
        $sformatf("%s TLP SIZE MISMATCH: TX=%0d DWs  RX=%0d DWs",
          tlp_kind, tx_pkt.tlp_q.size(), rx_pkt.tlp_q.size()))
      fail_cnt++;
      return;
    end

    begin
      bit pkt_pass = 1;
      foreach (tx_pkt.tlp_q[i]) begin
        if (tx_pkt.tlp_q[i] !== rx_pkt.tlp_q[i]) begin
          `uvm_error("FAIL",
            $sformatf("%s DW[%0d] MISMATCH — TX=%08h  RX=%08h",
              tlp_kind, i, tx_pkt.tlp_q[i], rx_pkt.tlp_q[i]))
          pkt_pass = 0;
        end
      end

      if (pkt_pass) begin
        pass_cnt++;
        `uvm_info("SCOREBOARD",
          $sformatf("%s TLP MATCH -- PASS (pass cnt=%0d, fail cnt=%0d)",
            tlp_kind, pass_cnt, fail_cnt), UVM_LOW)
        foreach (tx_pkt.tlp_q[i])
          `uvm_info("PASS",
            $sformatf("  TLP[%0d] TX=%08h  RX=%08h",
              i, tx_pkt.tlp_q[i], rx_pkt.tlp_q[i]), UVM_LOW)
      end else begin
        fail_cnt++;
        `uvm_error("FAIL",
          $sformatf("%s TLP MISMATCH (fail cnt=%0d)", tlp_kind, fail_cnt))
      end
    end

  endfunction

endclass

