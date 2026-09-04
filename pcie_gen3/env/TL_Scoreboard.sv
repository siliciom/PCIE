`uvm_analysis_imp_decl(_tr)
`uvm_analysis_imp_decl(_rr)

// TL_Scoreboard
// FIX #1 (root-cause of the mass UVM_ERROR cascade in the original
// sim.log):
//   The original forward_requests()/forward_completions() paired
//   TX and RX transactions purely by arrival order:
//   If either monitor ever mis-framed, dropped, or reordered a
//   single TLP, the two queues permanently lost 1:1 alignment, and
//   every following pop_front() compared unrelated transactions -
//   one root-cause event produced 6782 UVM_ERRORs.
//   Fix: key both sides by {req_id, tag} (the same key
//   Scoreboard_Top::rd_key() already uses) and only forward a pair
//   once both sides have an entry under the same key.
// FIX #2 (hang caused by the *first* rewrite of this fix):
//   That version signaled "something new arrived" with named
//   events (`-> cpl_available;` / `@(cpl_available)`). A named-
//   event trigger is fire-and-forget: if it fires while
//   forward_completions() is not literally parked on
//   drain loop from a previous match), the pulse is lost - there is
//   no queued/pending state. The task could then go back to sleep
//   on `@(cpl_available)` and block forever even though a valid
//   match already existed, hanging the whole run.
//   Fix: wake on plain scalar "push sequence" counters
//   (req_push_seq / cpl_push_seq), using the exact same
//   level-sensitive `wait(x != last_seen)` idiom the original file
//   already used reliably for the whole run via
//   is captured *before* draining, so any push that lands during
//   the drain (even one the drain loop doesn't pick up because a
//   match isn't ready yet) makes the counter differ from
//   immediately instead of blocking - so nothing can be missed.
//   The actual key matching (`find_ready_key`, which reads the
//   associative-array queues) is only ever called from ordinary
//   procedural code after waking, never from inside a `wait()`
//   expression, so there's no dependence on a simulator correctly
//   building sensitivity through a function call with `ref`
//   arguments into associative arrays - an area more likely to
//   vary between tools than a scalar integer compare.
class TL_Scoreboard extends uvm_component;

     `uvm_component_utils(TL_Scoreboard)

     uvm_analysis_imp_tr #(Sequence_item, TL_Scoreboard) TX_TL_Recv;
     uvm_analysis_imp_rr #(Sequence_item, TL_Scoreboard) RX_TL_Recv;
     uvm_analysis_port #(Sequence_item) t_port;
     uvm_analysis_port #(Sequence_item) r_port;

     // Queues-per-key: a given {req_id,tag} can legitimately see more
     // than one TLP in flight (e.g. split completions), so each key
     // maps to its own FIFO rather than assuming a single outstanding
     // transaction.
     Sequence_item tx_req_q[bit [23:0]][$];
     Sequence_item rx_req_q[bit [23:0]][$];
     Sequence_item tx_cpl_q[bit [23:0]][$];
     Sequence_item rx_cpl_q[bit [23:0]][$];

     // Wake conditions for the two forwarding tasks - see FIX #2 above.
     int unsigned req_push_seq;
     int unsigned cpl_push_seq;

     int unsigned req_forwarded_cnt;
     int unsigned cpl_forwarded_cnt;

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

     function automatic bit [23:0] key_of(Sequence_item pkt);
          return {pkt.req_id, pkt.tag};
     endfunction


     function void write_tr(Sequence_item tx_pkt);
          bit [23:0] key;

          `uvm_info("TL_Scoreboard", $sformatf(
                    "TX TL packet captured: %s fmt=%0b r_type=%0b length=%0d",
                    is_completion(
                        tx_pkt
                    ) ? "CPL" : "REQ",
                    tx_pkt.fmt,
                    tx_pkt.r_type,
                    tx_pkt.length
                    ), UVM_LOW)

          key = key_of(tx_pkt);

          if (is_completion(tx_pkt)) begin
               tx_cpl_q[key].push_back(tx_pkt);
               `uvm_info(
                   "WRITE_TX_TL_Scoreboard",
                   $sformatf(
                       "write_tr CPL key=%0h tx_cpl_q[key] size=%0d  fmt=%0b r_type=%0b lower_addr=%0b length=%0d e_type=%s",
                       key, tx_cpl_q[key].size(), tx_pkt.fmt, tx_pkt.r_type, tx_pkt.lower_addr,
                       tx_pkt.length, tx_pkt.e_type.name()), UVM_LOW)

               foreach (tx_pkt.payload[j])
                    `uvm_info("WRITE_TX_TL_Scoreboard", $sformatf(
                              "  tx_cpl payload[%0d] = %0h", j, tx_pkt.payload[j]), UVM_LOW)

               cpl_push_seq++;

          end else begin
               tx_req_q[key].push_back(tx_pkt);
               `uvm_info("WRITE_TX_TL_Scoreboard", $sformatf(
                         "write_tr REQ key=%0h tx_req_q[key] size=%0d  fmt=%0b r_type=%0b addr=%0h length=%0d e_type=%s",
                         key,
                         tx_req_q[key].size(),
                         tx_pkt.fmt,
                         tx_pkt.r_type,
                         tx_pkt.addr,
                         tx_pkt.length,
                         tx_pkt.e_type.name()
                         ), UVM_LOW)

               foreach (tx_pkt.payload[j])
                    `uvm_info("WRITE_TX_TL_Scoreboard", $sformatf(
                              "  tx_req payload[%0d] = %0h", j, tx_pkt.payload[j]), UVM_LOW)

               req_push_seq++;
          end

     endfunction


     function void write_rr(Sequence_item rx_pkt);
          bit [23:0] key;

          `uvm_info("TL_Scoreboard", $sformatf(
                    "RX TL packet captured: %s fmt=%0b r_type=%0b length=%0d",
                    is_completion(
                        rx_pkt
                    ) ? "CPL" : "REQ",
                    rx_pkt.fmt,
                    rx_pkt.r_type,
                    rx_pkt.length
                    ), UVM_LOW)

          key = key_of(rx_pkt);

          if (is_completion(rx_pkt)) begin
               rx_cpl_q[key].push_back(rx_pkt);
               `uvm_info(
                   "WRITE_RX_TL_Scoreboard",
                   $sformatf(
                       "write_rr CPL key=%0h rx_cpl_q[key] size=%0d  fmt=%0b r_type=%0b lower_addr=%0b  length=%0d e_type=%s",
                       key, rx_cpl_q[key].size(), rx_pkt.fmt, rx_pkt.r_type, rx_pkt.lower_addr,
                       rx_pkt.length, rx_pkt.e_type.name()), UVM_LOW)

               foreach (rx_pkt.payload[j])
                    `uvm_info("WRITE_RX_TL_Scoreboard", $sformatf(
                              "  rx_cpl payload[%0d] = %0h", j, rx_pkt.payload[j]), UVM_LOW)

               cpl_push_seq++;

          end else begin
               rx_req_q[key].push_back(rx_pkt);
               `uvm_info("WRITE_RX_TL_Scoreboard", $sformatf(
                         "write_rr REQ key=%0h rx_req_q[key] size=%0d  fmt=%0b r_type=%0b addr=%0h length=%0d e_type=%s",
                         key,
                         rx_req_q[key].size(),
                         rx_pkt.fmt,
                         rx_pkt.r_type,
                         rx_pkt.addr,
                         rx_pkt.length,
                         rx_pkt.e_type.name()
                         ), UVM_LOW)

               foreach (rx_pkt.payload[j])
                    `uvm_info("WRITE_RX_TL_Scoreboard", $sformatf(
                              "  rx_req payload[%0d] = %0h", j, rx_pkt.payload[j]), UVM_LOW)

               req_push_seq++;
          end

     endfunction


     task run_phase(uvm_phase phase);
          fork
               forward_requests();
               forward_completions();
          join
     endtask


     // Returns 1 and sets `key` to a key present (and non-empty) in
     // both `a` and `b`, or returns 0 if no such key exists yet. Only
     // ever called from plain procedural code (never from inside a
     function automatic bit find_ready_key(ref Sequence_item a[bit [23:0]][$],
                                           ref Sequence_item b[bit [23:0]][$],
                                           output bit [23:0] key);
          foreach (a[k]) begin
               if (a[k].size() > 0 && b.exists(k) && b[k].size() > 0) begin
                    key = k;
                    return 1;
               end
          end
          return 0;
     endfunction


     task forward_requests();
          bit [23:0] key;
          int unsigned last_seen;
          `uvm_info("SB", "Waiting for REQ packets", UVM_HIGH)
          forever begin
               wait (req_push_seq != last_seen);
               last_seen = req_push_seq;

               while (find_ready_key(
                   tx_req_q, rx_req_q, key
               )) begin
                    Sequence_item tx_pkt, rx_pkt;
                    tx_pkt = tx_req_q[key].pop_front();
                    rx_pkt = rx_req_q[key].pop_front();
                    if (tx_req_q[key].size() == 0) tx_req_q.delete(key);
                    if (rx_req_q[key].size() == 0) rx_req_q.delete(key);

                    `uvm_info("TL_Scoreboard", $sformatf(
                              "Forwarding matched REQUEST pair to Scoreboard_Top: key=%0h e_type=%s",
                              key,
                              tx_pkt.e_type.name()
                              ), UVM_LOW)

                    `uvm_info("TL_Scoreboard_REQ", $sformatf(
                              "TX REQ: fmt=%0b r_type=%0b addr=%0h length=%0d e_type=%s payload[0]=%0h",
                              tx_pkt.fmt,
                              tx_pkt.r_type,
                              tx_pkt.addr,
                              tx_pkt.length,
                              tx_pkt.e_type.name(),
                              (tx_pkt.payload.size() > 0) ? tx_pkt.payload[0] : 0
                              ), UVM_HIGH)

                    `uvm_info("TL_Scoreboard_REQ", $sformatf(
                              "RX REQ: fmt=%0b r_type=%0b addr=%0h length=%0d e_type=%s payload[0]=%0h",
                              rx_pkt.fmt,
                              rx_pkt.r_type,
                              rx_pkt.addr,
                              rx_pkt.length,
                              rx_pkt.e_type.name(),
                              (rx_pkt.payload.size() > 0) ? rx_pkt.payload[0] : 0
                              ), UVM_HIGH)

                    t_port.write(tx_pkt);
                    r_port.write(rx_pkt);
                    req_forwarded_cnt++;
               end
          end
     endtask


     task forward_completions();
          bit [23:0] key;
          int unsigned last_seen;
          forever begin
               wait (cpl_push_seq != last_seen);
               last_seen = cpl_push_seq;

               while (find_ready_key(
                   tx_cpl_q, rx_cpl_q, key
               )) begin
                    Sequence_item tx_pkt, rx_pkt;
                    tx_pkt = tx_cpl_q[key].pop_front();
                    rx_pkt = rx_cpl_q[key].pop_front();
                    if (tx_cpl_q[key].size() == 0) tx_cpl_q.delete(key);
                    if (rx_cpl_q[key].size() == 0) rx_cpl_q.delete(key);

                    `uvm_info("TL_Scoreboard", $sformatf(
                              "Forwarding matched COMPLETION pair to Scoreboard_Top: key=%0h e_type=%s",
                              key,
                              tx_pkt.e_type.name()
                              ), UVM_LOW)

                    `uvm_info("TL_Scoreboard_CPL", $sformatf(
                              "TX CPL: fmt=%0b r_type=%0b lower_addr=%0h length=%0d e_type=%s payload[0]=%0h",
                              tx_pkt.fmt,
                              tx_pkt.r_type,
                              tx_pkt.lower_addr,
                              tx_pkt.length,
                              tx_pkt.e_type.name(),
                              (tx_pkt.payload.size() > 0) ? tx_pkt.payload[0] : 0
                              ), UVM_HIGH)

                    `uvm_info("TL_Scoreboard_CPL", $sformatf(
                              "RX CPL: fmt=%0b r_type=%0b lower_addr=%0h length=%0d e_type=%s payload[0]=%0h",
                              rx_pkt.fmt,
                              rx_pkt.r_type,
                              rx_pkt.lower_addr,
                              rx_pkt.length,
                              rx_pkt.e_type.name(),
                              (rx_pkt.payload.size() > 0) ? rx_pkt.payload[0] : 0
                              ), UVM_HIGH)

                    t_port.write(tx_pkt);
                    r_port.write(rx_pkt);
                    cpl_forwarded_cnt++;
               end
          end
     endtask


     // Surfaces anything left orphaned (a TLP seen on only one side,
     // e.g. dropped on ECRC error, or never matched) instead of
     // silently ignoring it as the old FIFO-pairing scheme effectively
     // did once queues drifted.
     function void report_phase(uvm_phase phase);
          int unsigned orphan_req_tx, orphan_req_rx, orphan_cpl_tx, orphan_cpl_rx;
          super.report_phase(phase);

          foreach (tx_req_q[k]) orphan_req_tx += tx_req_q[k].size();
          foreach (rx_req_q[k]) orphan_req_rx += rx_req_q[k].size();
          foreach (tx_cpl_q[k]) orphan_cpl_tx += tx_cpl_q[k].size();
          foreach (rx_cpl_q[k]) orphan_cpl_rx += rx_cpl_q[k].size();

          `uvm_info("TL_Scoreboard", $sformatf(
                    "FINAL: requests matched=%0d completions matched=%0d | unmatched: tx_req=%0d rx_req=%0d tx_cpl=%0d rx_cpl=%0d",
                    req_forwarded_cnt,
                    cpl_forwarded_cnt,
                    orphan_req_tx,
                    orphan_req_rx,
                    orphan_cpl_tx,
                    orphan_cpl_rx
                    ), UVM_LOW)

          if (orphan_req_tx || orphan_req_rx || orphan_cpl_tx || orphan_cpl_rx)
               `uvm_warning("TL_Scoreboard",
                            "One or more TLPs were observed on only one side (TX or RX) and never matched - see counts above. This means a transaction was genuinely dropped/mis-captured, but - unlike before this fix - it no longer corrupts unrelated pairs.")
     endfunction

endclass

