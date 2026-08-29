class PCIe_MAC_Scoreboard extends uvm_scoreboard;
  `uvm_component_utils(PCIe_MAC_Scoreboard)

  `uvm_analysis_imp_decl(_rc_tx)
  `uvm_analysis_imp_decl(_rc_rx)
  `uvm_analysis_imp_decl(_ep_tx)
  `uvm_analysis_imp_decl(_ep_rx)

  uvm_analysis_imp_rc_tx #(Sequence_item, PCIe_MAC_Scoreboard) rc_tx_imp;
  uvm_analysis_imp_rc_rx #(Sequence_item, PCIe_MAC_Scoreboard) rc_rx_imp;
  uvm_analysis_imp_ep_tx #(Sequence_item, PCIe_MAC_Scoreboard) ep_tx_imp;
  uvm_analysis_imp_ep_rx #(Sequence_item, PCIe_MAC_Scoreboard) ep_rx_imp;

  Sequence_item rc_tx_q[$];
  Sequence_item rc_rx_q[$];
  Sequence_item ep_tx_q[$];
  Sequence_item ep_rx_q[$];

  static int PL_pass_cnt;
  static int PL_fail_cnt;

int rc_tx_cnt = 0;
int rc_rx_cnt = 0;
int ep_tx_cnt = 0;
int ep_rx_cnt = 0;



  function new(string name, uvm_component parent);
    super.new(name, parent);
    PL_pass_cnt=0;
    PL_fail_cnt=0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rc_tx_imp = new("rc_tx_imp", this);
    rc_rx_imp = new("rc_rx_imp", this);
    ep_tx_imp = new("ep_tx_imp", this);
    ep_rx_imp = new("ep_rx_imp", this);
  endfunction

 
  // RC's TX pipe data (what RC sends out) should show up as EP's RX pipe data
  function void write_rc_tx(Sequence_item item);
 rc_tx_cnt++;
 `uvm_info("MAC_SB_RC_TX",
            $sformatf("Received RC_TX packet. Queue size(before push)=%0d, Data=%p, Time=%0t",
                      rc_tx_q.size(),
                      item.pma_rc_tx_q,
                      $time),
            UVM_LOW)

    rc_tx_q.push_back(item);

 `uvm_info("RC_TX",
    $sformatf("RC_TX Count=%0d Queue=%0d",
              rc_tx_cnt, rc_tx_q.size()),
    UVM_LOW)

  endfunction

  function void write_ep_rx(Sequence_item item);
ep_rx_cnt++;
 `uvm_info("MAC_SB_EP_RX",
            $sformatf("Received EP_RX packet. Queue size(before push)=%0d, Data=%p, Time=%0t",
                      ep_rx_q.size(),
                      item.pma_ep_rx_q,
                      $time),
            UVM_LOW)

    ep_rx_q.push_back(item);

`uvm_info("EP_RX",
    $sformatf("EP_RX Count=%0d Queue=%0d",
              ep_rx_cnt, ep_rx_q.size()),
    UVM_LOW)


  endfunction

  // EP's TX pipe data (what EP sends out) should show up as RC's RX pipe data
  function void write_ep_tx(Sequence_item item);
 ep_tx_cnt++;
 `uvm_info("MAC_SB_EP_TX",
            $sformatf("Received EP_TX packet. Queue size(before push)=%0d, Data=%p, Time=%0t",
                      ep_tx_q.size(),
                      item.pma_ep_tx_q,
                      $time),
            UVM_LOW)

    ep_tx_q.push_back(item);

 `uvm_info("EP_TX",
    $sformatf("EP_TX Count=%0d Queue=%0d",
              ep_tx_cnt, ep_tx_q.size()),
    UVM_LOW)

  endfunction

  function void write_rc_rx(Sequence_item item);
 rc_rx_cnt++;
`uvm_info("MAC_SB_RC_RX",
            $sformatf("Received RC_RX packet. Queue size(before push)=%0d, Data=%p, Time=%0t",
                      rc_rx_q.size(),
                      item.pma_rc_rx_q,
                      $time),
            UVM_LOW)

    rc_rx_q.push_back(item);

  `uvm_info("RC_RX",
    $sformatf("RC_RX Count=%0d Queue=%0d",
              rc_rx_cnt, rc_rx_q.size()),
    UVM_LOW)


  endfunction


   task run_phase(uvm_phase phase);
    fork
      check_request1();
      check_completion1();
    join
  endtask




  // compare RC TX -> EP RX
  task check_request1();
    Sequence_item rc_item, ep_item;
    forever begin
    wait (rc_tx_q.size() > 0 && ep_rx_q.size() > 0);

 `uvm_info("REQ_CHECK",
      $sformatf("Before pop: RC_TX_Q=%0d EP_RX_Q=%0d",
                rc_tx_q.size(), ep_rx_q.size()),
      UVM_LOW)

      rc_item = rc_tx_q.pop_front();
      ep_item = ep_rx_q.pop_front();

 `uvm_info("REQ_CHECK",
      $sformatf("Comparing RC_TX(size=%0d) with EP_RX(size=%0d)",
                rc_item.pma_rc_tx_q.size(),
                ep_item.pma_ep_rx_q.size()),
      UVM_LOW)

      compare_tlp1(rc_item, ep_item, "REQUEST");
end
  
  endtask

  // compare EP TX -> RC RX
  task check_completion1();
    Sequence_item ep_item1, rc_item1;
    forever begin
    wait (ep_tx_q.size() > 0 && rc_rx_q.size() > 0);

 `uvm_info("CPL_CHECK",
      $sformatf("Before pop: EP_TX_Q=%0d RC_RX_Q=%0d",
                ep_tx_q.size(), rc_rx_q.size()),
      UVM_LOW)

      ep_item1 = ep_tx_q.pop_front();
      rc_item1 = rc_rx_q.pop_front();

 `uvm_info("CPL_CHECK",
      $sformatf("Comparing EP_TX(size=%0d) with RC_RX(size=%0d)",
                ep_item1.pma_ep_tx_q.size(),
                rc_item1.pma_rc_rx_q.size()),
      UVM_LOW)

      compare_tlp2(ep_item1,rc_item1, "COMPLETION");
     
   end     
  endtask
function void compare_tlp1(Sequence_item tx_pkt, Sequence_item rx_pkt, string kind);

bit match;
int first_bad = -1;
    match = (tx_pkt.pma_rc_tx_q.size() == rx_pkt.pma_ep_rx_q.size());
    if (match) begin
      foreach (tx_pkt.pma_rc_tx_q[i]) begin
        `uvm_info("SCB_MAC", $sformatf("[%s] word[%0d]  TX=%033h  RX=%033h",
                  kind, i, tx_pkt.pma_rc_tx_q[i], rx_pkt.pma_ep_rx_q[i]), UVM_HIGH)
        if (tx_pkt.pma_rc_tx_q[i] !== rx_pkt.pma_ep_rx_q[i]) begin
          match = 0; first_bad = i; break;
        end
      end
    end

    if (match) begin
      PL_pass_cnt++;
      `uvm_info("SCB_MAC", $sformatf("[%s] MATCH (pass cnt=%0d, %0d words)", kind, PL_pass_cnt, tx_pkt.pma_rc_tx_q.size()), UVM_LOW)
    end else begin
      PL_fail_cnt++;
      `uvm_error("SCB_MAC",
                 $sformatf("[%s] PHY-word MISMATCH (fail cnt=%0d) %s\n  TX(size=%0d)=%p\n  RX(size=%0d)=%p",
                           kind, PL_fail_cnt,
                           (first_bad>=0) ? $sformatf("first bad word index=%0d", first_bad) : "size mismatch",
                           tx_pkt.pma_rc_tx_q.size(), tx_pkt.pma_rc_tx_q,
                           rx_pkt.pma_ep_rx_q.size(), rx_pkt.pma_ep_rx_q))
    end


endfunction


function void compare_tlp2(Sequence_item ep_item, Sequence_item rc_item, string kind);

 

 bit match;
 int first_bad = -1;
    match = (ep_item.pma_ep_tx_q.size() == rc_item.pma_rc_rx_q.size());
    if (match) begin
      foreach (ep_item.pma_ep_tx_q[i]) begin
        `uvm_info("SCB_MAC", $sformatf("[%s] word[%0d]  EP_TX=%033h  RC_RX=%033h",
                  kind, i, ep_item.pma_ep_tx_q[i], rc_item.pma_rc_rx_q[i]), UVM_HIGH)
        if (ep_item.pma_ep_tx_q[i] !== rc_item.pma_rc_rx_q[i]) begin
          match = 0; first_bad = i; break;
        end
      end
    end

    if (match) begin
      PL_pass_cnt++;
      `uvm_info("SCB_MAC", $sformatf("[%s] MATCH (pass cnt=%0d, %0d words)", kind, PL_pass_cnt, ep_item.pma_ep_tx_q.size()), UVM_LOW)
    end else begin
      PL_fail_cnt++;
      `uvm_error("SCB_MAC",
                 $sformatf("[%s] PHY-word MISMATCH (fail cnt=%0d) %s\n  EP_TX(size=%0d)=%p\n  RC_RX(size=%0d)=%p",
                           kind, PL_fail_cnt,
                           (first_bad>=0) ? $sformatf("first bad word index=%0d", first_bad) : "size mismatch",
                           ep_item.pma_ep_tx_q.size(), ep_item.pma_ep_tx_q,
                           rc_item.pma_rc_rx_q.size(), rc_item.pma_rc_rx_q))
    end



endfunction


function void report_phase(uvm_phase phase);
    `uvm_info("SB12",
              $sformatf("PCIe_MAC_Scoreboard FINAL RESULT: pass=%0d fail=%0d", PL_pass_cnt, PL_fail_cnt),
              UVM_LOW)

  `uvm_info("SB_REPORT",
    $sformatf("\n\
RC_TX Transactions = %0d\n\
EP_RX Transactions = %0d\n\
EP_TX Transactions = %0d\n\
RC_RX Transactions = %0d\n\
PASS = %0d\n\
FAIL = %0d",
      rc_tx_cnt,
      ep_rx_cnt,
      ep_tx_cnt,
      rc_rx_cnt,
      PL_pass_cnt,
      PL_fail_cnt),
    UVM_NONE)


  endfunction

 
endclass
