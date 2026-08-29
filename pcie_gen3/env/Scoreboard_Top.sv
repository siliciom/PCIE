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

  bit [31:0] mem[bit[63:0]];

  
  typedef struct {
    bit [63:0] addr;
    bit [9:0]  length;       
    int        received_dw;  
    bit        any_mismatch; 
  } pending_rd_s;
  pending_rd_s pending_reads[bit[23:0]];

  static int mem_pass_cnt;
  static int mem_fail_cnt;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    fail_cnt = 0;
    pass_cnt = 0;
    mem_pass_cnt = 0;
    mem_fail_cnt = 0;
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    t_imp = new("t_imp", this);
    r_imp = new("r_imp", this);
  endfunction

  function automatic bit is_completion(Sequence_item pkt);
    return (pkt.e_type == CPL || pkt.e_type == CPL_DATA);
  endfunction

  function automatic bit [23:0] rd_key(Sequence_item pkt);
    return {pkt.req_id, pkt.tag};
  endfunction

  virtual function void write_t(Sequence_item tx_pkt);
    if (is_completion(tx_pkt)) begin
      tx_cpl_q.push_back(tx_pkt);
      `uvm_info("SCOREBOARD8",
        $sformatf("write_t: CPL queued, tx_cpl_q size=%0d e_type=%s",
          tx_cpl_q.size(), tx_pkt.e_type.name()), UVM_LOW)
    end
    else begin
      tx_req_q.push_back(tx_pkt);
      `uvm_info("SCOREBOARD8",
        $sformatf("write_t: REQ queued, tx_req_q size=%0d e_type=%s",
          tx_req_q.size(), tx_pkt.e_type.name()), UVM_LOW)
    end
  endfunction

  virtual function void write_r(Sequence_item rx_pkt);
    if (is_completion(rx_pkt)) begin
      rx_cpl_q.push_back(rx_pkt);
      `uvm_info("SCOREBOARD8",
        $sformatf("write_r: CPL queued, rx_cpl_q size=%0d e_type=%s",
          rx_cpl_q.size(), rx_pkt.e_type.name()), UVM_LOW)
    end else begin
      rx_req_q.push_back(rx_pkt);
      `uvm_info("SCOREBOARD8",
        $sformatf("write_r: REQ queued, rx_req_q size=%0d e_type=%s",
          rx_req_q.size(), rx_pkt.e_type.name()), UVM_LOW)
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
      `uvm_info("DEBUG1", "Entered check_requests()", UVM_LOW)
      tx_pkt = tx_req_q.pop_front();
      rx_pkt = rx_req_q.pop_front();
      `uvm_info("DEBUG123",
        $sformatf("TX: req_id=%0h tag=%0h type=%s | RX: req_id=%0h tag=%0h type=%s",
          tx_pkt.req_id, tx_pkt.tag, tx_pkt.e_type.name(),
          rx_pkt.req_id, rx_pkt.tag, rx_pkt.e_type.name()),
        UVM_LOW)
      compare_tlp(tx_pkt, rx_pkt, "REQUEST");

      if (rx_pkt.e_type == MEM_WR) begin
        mem_write(rx_pkt);
      end
      else if (rx_pkt.e_type == MEM_RD) begin
        mem_register_read(rx_pkt);
      end
    end
  endtask

  task check_completions();
    Sequence_item tx_pkt, rx_pkt;
    forever begin
      wait(tx_cpl_q.size() > 0 && rx_cpl_q.size() > 0);
      `uvm_info("DEBUG2","Entered check_completions()",UVM_LOW)
      tx_pkt = tx_cpl_q.pop_front();
      rx_pkt = rx_cpl_q.pop_front();
      `uvm_info("DEBUG2", $sformatf("tx_pkt.e_type=%s", tx_pkt.e_type.name()), UVM_LOW)
      compare_tlp(tx_pkt, rx_pkt, "COMPLETION");

      if (tx_pkt.e_type == CPL_DATA) begin
        bit [23:0] k = rd_key(tx_pkt);
        if (pending_reads.exists(k)) begin
          mem_check_completion(tx_pkt);
        end
        else begin
          `uvm_info("MEM_MODEL_DEBUG",
            $sformatf("CPL_DATA for req_id=%0h tag=%0h has no pending MEM_RD (likely IO_RD/CFG_RD) - skipping mem check",
              tx_pkt.req_id, tx_pkt.tag), UVM_LOW)
        end
      end
    end
  endtask

  function automatic void write_dw_with_be(bit [63:0] a, bit [31:0] data, bit [3:0] be);
    bit [31:0] old_val;
    bit [31:0] merged;
    old_val = mem.exists(a) ? mem[a] : 32'h0;
    merged  = old_val;
    if (be[0]) merged[7:0]   = data[7:0];
    if (be[1]) merged[15:8]  = data[15:8];
    if (be[2]) merged[23:16] = data[23:16];
    if (be[3]) merged[31:24] = data[31:24];
    mem[a] = merged;
  endfunction

  function automatic void mem_write(Sequence_item pkt);
    bit [63:0] a;
    int n;

    // ERR_EP_POISON policy: a completer must not consume the
    // data payload of a poisoned (EP=1) write - the poison
    // indication is what matters, not the bytes. Drop the write
    // instead of applying it to the memory model, and flag it so
    // the negative test can confirm the poisoned data never landed.
    if (pkt.ep) begin
      `uvm_error("MALFORMED_TLP",
        $sformatf("Poisoned MEM_WR (EP=1) received addr=%0h tag=%0h - dropping payload per completer policy",
                   pkt.addr, pkt.tag))
      return;
    end

    a = pkt.addr;
    n = pkt.payload.size();
    foreach (pkt.payload[i]) begin
      bit [3:0] be;
      if (n == 1)
        be = pkt.first_BE;
      else if (i == 0)
        be = pkt.first_BE;
      else if (i == n-1)
        be = pkt.last_BE;
      else
        be = 4'b1111;

      write_dw_with_be(a, pkt.payload[i], be);

      `uvm_info("MEM_MODEL",
        $sformatf("MEM WRITE  addr=%0h  data=%08h  be=%0b  stored=%08h",
          a, pkt.payload[i], be, mem[a]), UVM_LOW)
      a += 4;
    end
  endfunction

  function automatic void mem_register_read(Sequence_item pkt);
    bit [23:0] key;
    key = rd_key(pkt);
    `uvm_info("MEM_MODEL_DEBUG",
      $sformatf("REGISTERING key=%0h req_id=%0h tag=%0h addr=%0h length=%0d",
        key, pkt.req_id, pkt.tag, pkt.addr, pkt.length), UVM_LOW)

    if (pending_reads.exists(key)) begin
      `uvm_warning("MEM_MODEL",
        $sformatf("Duplicate outstanding read for req_id=%0h tag=%0h — overwriting",
          pkt.req_id, pkt.tag))
    end
    pending_reads[key].addr         = pkt.addr;
    pending_reads[key].length       = pkt.length;
    pending_reads[key].received_dw  = 0;
    pending_reads[key].any_mismatch = 0;
    `uvm_info("MEM_MODEL",
      $sformatf("MEM_RD REGISTERED  req_id=%0h tag=%0h addr=%0h length=%0d",
        pkt.req_id, pkt.tag, pkt.addr, pkt.length), UVM_LOW)
  endfunction

 
  function automatic void mem_check_completion(Sequence_item pkt);
    bit [23:0]   key;
    pending_rd_s rd;
    bit [63:0]   a;
    bit          frag_pass;

    key = rd_key(pkt);

    `uvm_info("MEM_MODEL_DEBUG",
      $sformatf("LOOKING UP key=%0h req_id=%0h tag=%0h lower_addr=%0h byte_count=%0d payload_dw=%0d",
        key, pkt.req_id, pkt.tag, pkt.lower_addr, pkt.byte_count, pkt.payload.size()), UVM_LOW)

    if (!pending_reads.exists(key)) begin
      `uvm_error("MEM_MODEL",
        $sformatf("Unmatched CPL_DATA — no outstanding MEM_RD for req_id=%0h tag=%0h",
          pkt.req_id, pkt.tag))
      mem_fail_cnt++;
      return;
    end

    rd = pending_reads[key];

    a = rd.addr + (rd.received_dw * 4);

`uvm_info("MEM_MODEL_DEBUG",
  $sformatf(
    "CPL TRACE: req_id=%0h tag=%0h rd_addr=%0h received_dw=%0d length=%0d payload_dw=%0d lower_addr=%0h byte_count=%0d",
    pkt.req_id,
    pkt.tag,
    rd.addr,
    rd.received_dw,
    rd.length,
    pkt.payload.size(),
    pkt.lower_addr,
    pkt.byte_count
  ),
  UVM_LOW)


    frag_pass = 1;

    foreach (pkt.payload[i]) begin
      bit [31:0] expected;
      expected = mem.exists(a) ? mem[a] : 32'h0;
      if (pkt.payload[i] !== expected) begin
        `uvm_error("MEM_MODEL",
          $sformatf("MEM READ MISMATCH  addr=%0h  expected=%08h  got=%08h  req_id=%0h tag=%0h",
            a, expected, pkt.payload[i], pkt.req_id, pkt.tag))
        frag_pass = 0;
      end
      else begin
        `uvm_info("MEM_MODEL_PASS",
          $sformatf("MEM READ MATCH     addr=%0h  data=%08h  req_id=%0h tag=%0h",
            a, pkt.payload[i], pkt.req_id, pkt.tag), UVM_LOW)
      end
      a += 4;
    end

    rd.received_dw  += pkt.payload.size();
    rd.any_mismatch  = rd.any_mismatch | ~frag_pass;
    pending_reads[key] = rd;

  
    if (pkt.byte_count == pkt.payload.size() * 4) begin
      if (!rd.any_mismatch && (rd.received_dw == rd.length)) begin
        mem_pass_cnt++;
        `uvm_info("MEM_MODEL",
          $sformatf("MEM_RD/CPL_DATA MATCH (mem_pass_cnt=%0d) req_id=%0h tag=%0h",
            mem_pass_cnt, pkt.req_id, pkt.tag), UVM_LOW)
      end
      else begin
        mem_fail_cnt++;
        `uvm_error("MEM_MODEL",
          $sformatf("MEM_RD/CPL_DATA MISMATCH (mem_fail_cnt=%0d) req_id=%0h tag=%0h — received_dw=%0d expected_length=%0d any_mismatch=%0b",
            mem_fail_cnt, pkt.req_id, pkt.tag, rd.received_dw, rd.length, rd.any_mismatch))
      end
      pending_reads.delete(key);
    end
    else begin
      `uvm_info("MEM_MODEL_DEBUG",
        $sformatf("Fragment processed (pass=%0b), more expected — req_id=%0h tag=%0h received_dw=%0d/%0d",
          frag_pass, pkt.req_id, pkt.tag, rd.received_dw, rd.length), UVM_LOW)
    end
  endfunction

  // Full aligned TX-vs-RX dump for a mismatched packet pair. One row
  // per DW; '*' flags the differing rows; header rows are decoded.
  function string diff_dump(Sequence_item tx_pkt, Sequence_item rx_pkt, string tlp_kind);
    int n = (tx_pkt.tlp_q.size() > rx_pkt.tlp_q.size()) ? tx_pkt.tlp_q.size() : rx_pkt.tlp_q.size();
    string s = $sformatf("\n==== %s DIFF  TX[uid=%0d %s] (%0d DW)  vs  RX[uid=%0d %s] (%0d DW) ====\n",
                         tlp_kind, tx_pkt.pkt_uid, tx_pkt.type_str(), tx_pkt.tlp_q.size(),
                         rx_pkt.pkt_uid, rx_pkt.type_str(), rx_pkt.tlp_q.size());
    for (int i = 0; i < n; i++) begin
      bit has_tx = (i < tx_pkt.tlp_q.size());
      bit has_rx = (i < rx_pkt.tlp_q.size());
      bit diff   = (!has_tx || !has_rx || (tx_pkt.tlp_q[i] !== rx_pkt.tlp_q[i]));
      s = {s, $sformatf("  %s DW[%0d]  TX=%s  RX=%s\n",
                        diff ? "*" : " ", i,
                        has_tx ? $sformatf("%08h", tx_pkt.tlp_q[i]) : "--------",
                        has_rx ? $sformatf("%08h", rx_pkt.tlp_q[i]) : "--------")};
    end
    return s;
  endfunction

  function void compare_tlp(Sequence_item tx_pkt, Sequence_item rx_pkt,
                             string tlp_kind);
    if (tx_pkt.tlp_q.size() !== rx_pkt.tlp_q.size()) begin
      fail_cnt++;
      `uvm_error("SCB_TOP",
        $sformatf("%s TLP SIZE MISMATCH: TX=%0d DW  RX=%0d DW (fail cnt=%0d)%s",
          tlp_kind, tx_pkt.tlp_q.size(), rx_pkt.tlp_q.size(), fail_cnt,
          diff_dump(tx_pkt, rx_pkt, tlp_kind)))
      return;
    end
    begin
      bit pkt_pass = 1;
      foreach (tx_pkt.tlp_q[i])
        if (tx_pkt.tlp_q[i] !== rx_pkt.tlp_q[i]) pkt_pass = 0;

      if (pkt_pass) begin
        pass_cnt++;
        `uvm_info("SCB_TOP",
          $sformatf("%s TLP MATCH (pass cnt=%0d)  ->  %s", tlp_kind, pass_cnt, tx_pkt.convert2string()), UVM_LOW)
      end else begin
        fail_cnt++;
        `uvm_error("SCB_TOP",
          $sformatf("%s TLP DATA MISMATCH (fail cnt=%0d)%s", tlp_kind, fail_cnt,
            diff_dump(tx_pkt, rx_pkt, tlp_kind)))
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    string s;
    super.report_phase(phase);

    s = "\n================ Scoreboard_Top SUMMARY ================\n";
    s = {s, $sformatf("  TLP transport compare : pass=%0d  fail=%0d\n", pass_cnt, fail_cnt)};
    s = {s, $sformatf("  Memory read compare   : pass=%0d  fail=%0d\n", mem_pass_cnt, mem_fail_cnt)};
    s = {s, $sformatf("  mem model entries     : %0d DW written\n", mem.num())};
    s = {s, $sformatf("  UNDRAINED queues      : tx_req=%0d rx_req=%0d tx_cpl=%0d rx_cpl=%0d\n",
                      tx_req_q.size(), rx_req_q.size(), tx_cpl_q.size(), rx_cpl_q.size())};
    s = {s, $sformatf("  OUTSTANDING reads     : %0d\n", pending_reads.num())};
    if (pending_reads.num() > 0) begin
      bit [23:0] k;
      if (pending_reads.first(k))
        do s = {s, $sformatf("     key=%06h addr=%016h length=%0d received_dw=%0d\n",
                             k, pending_reads[k].addr, pending_reads[k].length, pending_reads[k].received_dw)};
        while (pending_reads.next(k));
    end
    s = {s, "======================================================="};
    `uvm_info("SCB_TOP", s, UVM_NONE)
  endfunction

endclass
