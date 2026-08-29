`uvm_analysis_imp_decl(_rc_tx)
`uvm_analysis_imp_decl(_rc_rx)
`uvm_analysis_imp_decl(_ep_tx)
`uvm_analysis_imp_decl(_ep_rx)
`uvm_analysis_imp_decl(_rc_dllp_tx)
`uvm_analysis_imp_decl(_rc_dllp_rx)
`uvm_analysis_imp_decl(_ep_dllp_tx)
`uvm_analysis_imp_decl(_ep_dllp_rx)

class DL_Scoreboard extends uvm_scoreboard;
  `uvm_component_utils(DL_Scoreboard)

  uvm_analysis_imp_rc_tx #(Sequence_item, DL_Scoreboard) rc_tx_imp;
  uvm_analysis_imp_rc_rx #(Sequence_item, DL_Scoreboard) rc_rx_imp;
  uvm_analysis_imp_ep_tx #(Sequence_item, DL_Scoreboard) ep_tx_imp;
  uvm_analysis_imp_ep_rx #(Sequence_item, DL_Scoreboard) ep_rx_imp;


  Sequence_item rc_tx_q[$];   // RC   -> link : DLP Request  (sent)
  Sequence_item ep_rx_q[$];   // link -> EP   : DLP Request  (received)

  Sequence_item ep_tx_q[$];   // EP   -> link : Completion   (sent)
  Sequence_item rc_rx_q[$];   // link -> RC   : Completion   (received)


  static int DL_fail_cnt;
  static int DL_pass_cnt;

uvm_analysis_imp_rc_dllp_tx #(Sequence_item, DL_Scoreboard) rc_dllp_tx_imp;
uvm_analysis_imp_rc_dllp_rx #(Sequence_item, DL_Scoreboard) rc_dllp_rx_imp;
uvm_analysis_imp_ep_dllp_tx #(Sequence_item, DL_Scoreboard) ep_dllp_tx_imp;
uvm_analysis_imp_ep_dllp_rx #(Sequence_item, DL_Scoreboard) ep_dllp_rx_imp;

Sequence_item rc_dllp_tx_q[$];   // RC sent
Sequence_item ep_dllp_rx_q[$];   // EP received  (should match rc_dllp_tx_q)
Sequence_item ep_dllp_tx_q[$];   // EP sent
Sequence_item rc_dllp_rx_q[$];   // RC received  (should match ep_dllp_tx_q)

static int DLLP_pass_cnt;
static int DLLP_fail_cnt;



  function new(string name = "DL_Scoreboard", uvm_component parent = null);
    super.new(name, parent);
    DL_fail_cnt = 0;
    DL_pass_cnt = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rc_tx_imp = new("rc_tx_imp", this);
    rc_rx_imp = new("rc_rx_imp", this);
    ep_tx_imp = new("ep_tx_imp", this);
    ep_rx_imp = new("ep_rx_imp", this);

rc_dllp_tx_imp = new("rc_dllp_tx_imp", this);
rc_dllp_rx_imp = new("rc_dllp_rx_imp", this);
ep_dllp_tx_imp = new("ep_dllp_tx_imp", this);
ep_dllp_rx_imp = new("ep_dllp_rx_imp", this);


  endfunction

  function void write_rc_tx(Sequence_item pkt);
    rc_tx_q.push_back(pkt);
    `uvm_info("DL_SCB", $sformatf("RC_TX queued (depth=%0d)", rc_tx_q.size()), UVM_HIGH)
  endfunction

  function void write_ep_rx(Sequence_item pkt);
    ep_rx_q.push_back(pkt);
    `uvm_info("DL_SCB", $sformatf("EP_RX queued (depth=%0d)", ep_rx_q.size()), UVM_HIGH)
  endfunction

  function void write_ep_tx(Sequence_item pkt);
    ep_tx_q.push_back(pkt);
    `uvm_info("DL_SCB", $sformatf("EP_TX queued (depth=%0d)", ep_tx_q.size()), UVM_HIGH)
  endfunction

  function void write_rc_rx(Sequence_item pkt);
    rc_rx_q.push_back(pkt);
    `uvm_info("DL_SCB", $sformatf("RC_RX queued (depth=%0d)", rc_rx_q.size()), UVM_HIGH)
  endfunction




  function void write_rc_dllp_tx(Sequence_item pkt);
  rc_dllp_tx_q.push_back(pkt);
  `uvm_info("DL_SCB", $sformatf("RC_DLLP_TX queued (depth=%0d)", rc_dllp_tx_q.size()), UVM_HIGH)
endfunction

function void write_ep_dllp_rx(Sequence_item pkt);
  ep_dllp_rx_q.push_back(pkt);
  `uvm_info("DL_SCB", $sformatf("EP_DLLP_RX queued (depth=%0d)", ep_dllp_rx_q.size()), UVM_HIGH)
endfunction

function void write_ep_dllp_tx(Sequence_item pkt);
  ep_dllp_tx_q.push_back(pkt);
  `uvm_info("DL_SCB", $sformatf("EP_DLLP_TX queued (depth=%0d)", ep_dllp_tx_q.size()), UVM_HIGH)
endfunction

function void write_rc_dllp_rx(Sequence_item pkt);
  rc_dllp_rx_q.push_back(pkt);
  `uvm_info("DL_SCB", $sformatf("RC_DLLP_RX queued (depth=%0d)", rc_dllp_rx_q.size()), UVM_HIGH)
endfunction

  task run_phase(uvm_phase phase);
    fork
      check_request();
      check_completion();
      check_dllp_rc_to_ep();
    check_dllp_ep_to_rc();
    join
  endtask

 
  task check_request();
    Sequence_item rc_item, ep_item;
    forever begin
      wait (rc_tx_q.size() && ep_rx_q.size());
      rc_item = rc_tx_q.pop_front();
      ep_item = ep_rx_q.pop_front();
      compare_tlp1(rc_item, ep_item, "REQUEST");
    end
  endtask


  task check_completion();
    Sequence_item ep_item1, rc_item1;
    forever begin
      wait (ep_tx_q.size() && rc_rx_q.size());
      ep_item1 = ep_tx_q.pop_front();
      rc_item1 = rc_rx_q.pop_front();
      compare_tlp2(ep_item1, rc_item1, "COMPLETION");
    end
  endtask


  task check_dllp_rc_to_ep();
  Sequence_item rc_item2, ep_item2;
  forever begin
    wait (rc_dllp_tx_q.size() && ep_dllp_rx_q.size());
    rc_item2 = rc_dllp_tx_q.pop_front();
    ep_item2 = ep_dllp_rx_q.pop_front();
    compare_dllp1(rc_item2, ep_item2, "DLLP RC->EP");
  end
endtask

task check_dllp_ep_to_rc();
  Sequence_item ep_item3, rc_item3;
  forever begin
    wait (ep_dllp_tx_q.size() && rc_dllp_rx_q.size());
    ep_item3 = ep_dllp_tx_q.pop_front();
    rc_item3 = rc_dllp_rx_q.pop_front();
    compare_dllp2(ep_item3, rc_item3, "DLLP EP->RC");
  end
endtask

 
  // Shared DW-list compare + full aligned diff dump on mismatch.
  // NOTE: pass/fail logic is UNCHANGED from the original compare_tlp1/2
  // (iterates TX indices only, no size gate - so extra RX DWs are not
  // flagged; that hardening is punch-list #5, tracked separately). The
  // dump still SHOWS the size difference for debug.
  function void dl_compare(bit [31:0] tx_q[$],
                           bit [31:0] rx_q[$],
                           string tlp_kind);
    bit    ok = 1;
    int    n  = (tx_q.size() > rx_q.size()) ? tx_q.size() : rx_q.size();
    string dump;

    foreach (tx_q[i])
      if (tx_q[i] !== rx_q[i]) ok = 0;   // out-of-range rx_q[i] reads as 0, same as the original

    if (ok) begin
      DL_pass_cnt++;
      `uvm_info("SCB_DL", $sformatf("%s DLP MATCH (pass cnt=%0d, %0d DW)", tlp_kind, DL_pass_cnt, tx_q.size()), UVM_LOW)
      return;
    end

    DL_fail_cnt++;
    dump = $sformatf("\n==== %s DLP DIFF  TX=%0d DW  RX=%0d DW ====\n", tlp_kind, tx_q.size(), rx_q.size());
    for (int i = 0; i < n; i++) begin
      bit has_tx = (i < tx_q.size());
      bit has_rx = (i < rx_q.size());
      bit diff   = (!has_tx || !has_rx || tx_q[i] !== rx_q[i]);
      dump = {dump, $sformatf("  %s DW[%0d]  TX=%s  RX=%s\n", diff ? "*" : " ", i,
                              has_tx ? $sformatf("%08h", tx_q[i]) : "--------",
                              has_rx ? $sformatf("%08h", rx_q[i]) : "--------")};
    end
    `uvm_error("SCB_DL", $sformatf("%s DLP MISMATCH (fail cnt=%0d)%s", tlp_kind, DL_fail_cnt, dump))
  endfunction

  function void compare_tlp1(Sequence_item tx_pkt, Sequence_item rx_pkt, string tlp_kind);
    dl_compare(tx_pkt.tx_data_sb, rx_pkt.ep_req_data_sb, tlp_kind);
  endfunction

  function void compare_tlp2(Sequence_item tx_pkt, Sequence_item rx_pkt, string tlp_kind);
    dl_compare(tx_pkt.rx_data_sb, rx_pkt.rc_com_data_sb, tlp_kind);
  endfunction

 function void compare_dllp1(Sequence_item tx_pkt, Sequence_item rx_pkt, string tlp_kind);

    bit pkt_pass = 1;

    foreach (tx_pkt.rc_dllp_data_sb[i]) begin
      if (tx_pkt.rc_dllp_data_sb[i] !== rx_pkt.rc_dllp_packet_sb[i]) begin
        `uvm_error("FAIL",
          $sformatf("%s DW[%0d] MISMATCH — TX=%08h  RX=%08h",
            tlp_kind, i, tx_pkt.rc_dllp_data_sb[i], rx_pkt.rc_dllp_packet_sb[i]))
        pkt_pass = 0;
      end
    end

    if (pkt_pass) begin
      DLLP_pass_cnt++;
      `uvm_info("DL_SCOREBOARD",
        $sformatf("%s DLLP MATCH (pass cnt=%0d)", tlp_kind, DLLP_pass_cnt), UVM_LOW)
      foreach (tx_pkt.rc_dllp_data_sb[i])
        `uvm_info("PASS",
          $sformatf("  DLLP[%0d] TX=%08h  RX=%08h",
            i, tx_pkt.rc_dllp_data_sb[i], rx_pkt.rc_dllp_packet_sb[i]), UVM_LOW)
    end
    else begin
      DLLP_fail_cnt++;
      `uvm_error("FAIL",
        $sformatf("%s DLLP MISMATCH (fail cnt=%0d)", tlp_kind, DLLP_fail_cnt))
    end

  endfunction

function void compare_dllp2(Sequence_item tx_pkt, Sequence_item rx_pkt, string tlp_kind);

    bit pkt_pass = 1;

    foreach (tx_pkt.ep_dllp_data_sb[i]) begin
      if (tx_pkt.ep_dllp_data_sb[i] !== rx_pkt.ep_dllp_packet_sb[i]) begin
        `uvm_error("FAIL",
          $sformatf("%s DW[%0d] MISMATCH — TX=%08h  RX=%08h",
            tlp_kind, i, tx_pkt.ep_dllp_data_sb[i], rx_pkt.ep_dllp_packet_sb[i]))
        pkt_pass = 0;
      end
    end

    if (pkt_pass) begin
      DLLP_pass_cnt++;
      `uvm_info("DL_SCOREBOARD",
        $sformatf("%s DLLP MATCH (pass cnt=%0d)", tlp_kind, DLLP_pass_cnt), UVM_LOW)
      foreach (tx_pkt.ep_dllp_data_sb[i])
        `uvm_info("PASS",
          $sformatf("  DLLP[%0d] TX=%08h  RX=%08h",
            i, tx_pkt.ep_dllp_data_sb[i], rx_pkt.ep_dllp_packet_sb[i]), UVM_LOW)
    end
    else begin
      DLLP_fail_cnt++;
      `uvm_error("FAIL",
        $sformatf("%s DLLP MISMATCH (fail cnt=%0d)", tlp_kind, DLLP_fail_cnt))
    end

  endfunction

  function void report_phase(uvm_phase phase);
    string s;
    super.report_phase(phase);
    s = "\n================ DL_Scoreboard SUMMARY ================\n";
    s = {s, $sformatf("  DLP  compare : pass=%0d  fail=%0d\n", DL_pass_cnt, DL_fail_cnt)};
    s = {s, $sformatf("  DLLP compare : pass=%0d  fail=%0d\n", DLLP_pass_cnt, DLLP_fail_cnt)};
    s = {s, $sformatf("  UNDRAINED queues: rc_tx=%0d ep_rx=%0d ep_tx=%0d rc_rx=%0d | dllp rc_tx=%0d ep_rx=%0d ep_tx=%0d rc_rx=%0d\n",
                      rc_tx_q.size(), ep_rx_q.size(), ep_tx_q.size(), rc_rx_q.size(),
                      rc_dllp_tx_q.size(), ep_dllp_rx_q.size(), ep_dllp_tx_q.size(), rc_dllp_rx_q.size())};
    s = {s, "====================================================="};
    `uvm_info("SCB_DL", s, UVM_NONE)
  endfunction



    
endclass : DL_Scoreboard
