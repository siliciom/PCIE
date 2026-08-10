//-----------------------------------------------------------------
// VC_Arbiter
//   Sits between the sequencer and TX_TL_Driver. Buffers items into
//   one queue per VC (8 total) and hands the driver the next item
//   to transmit using STRICT-PRIORITY arbitration:
//
//     VC7 (highest) > VC6 > VC5 > VC4 > VC3 > VC2 > VC1 > VC0 (lowest)
//
//   A VC is only skipped if it's empty OR its head-of-line packet
//   doesn't have sufficient flow-control credit yet (checked via
//   FC_Manager, which is now itself per-VC). This means a higher VC
//   that is credit-starved does NOT block a lower VC from moving -
//   matches real PCIe TL behavior (arbitration and FC are separate
//   but cooperating mechanisms).
//
//   Feeding items in: call push() from wherever items currently
//   arrive (e.g. have the sequence/driver call push() right after
//   seq_item_port.get_next_item() instead of driving directly).
//-----------------------------------------------------------------
class VC_Arbiter extends uvm_component;

  `uvm_component_utils(VC_Arbiter)

  Sequence_item vc_q[8][$];   // one TX queue per VC
  FC_Manager    fc_mgr;

  // Starvation visibility: counts consecutive arbitration cycles
  // a non-empty VC was passed over in favor of a higher VC.
  int starve_count[8];

  function new(string name = "VC_Arbiter", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(FC_Manager)::get(this, "", "fc_mgr", fc_mgr))
      `uvm_fatal("VC_Arbiter", "Unable to get FC Manager")
  endfunction

  // Called by whatever currently produces Sequence_items (sequencer
  // consumer / driver) once vc has been resolved (post_randomize).
  function void push(Sequence_item item);
    vc_q[item.vc].push_back(item);
    `uvm_info("VC_Arbiter", $sformatf("Enqueued item on VC%0d (queue depth=%0d)", item.vc, vc_q[item.vc].size()), UVM_HIGH)
  endfunction

  function bit any_pending();
    foreach (vc_q[v]) if (vc_q[v].size() != 0) return 1;
    return 0;
  endfunction

  //-----------------------------------------------------------
  // Strict-priority selection. Blocks until some VC has both an
  // item AND sufficient credit for it. Returns the winning item
  // and its vc.
  //-----------------------------------------------------------
  task get_next(output Sequence_item item, output vc_id_e vc_won, ref virtual TX_TL_DL_Interface TX_TL_DL);

    forever begin

      for (int v = 7; v >= 0; v--) begin

        if (vc_q[v].size() != 0) begin

          if (fc_mgr.has_sufficient_credit(vc_id_e'(v), vc_q[v][0])) begin

            item   = vc_q[v].pop_front();
            vc_won = vc_id_e'(v);

            // reset starvation tracking for the VC that won,
            // bump it for every non-empty VC below it that lost out
            starve_count[v] = 0;
            for (int lower = v-1; lower >= 0; lower--)
              if (vc_q[lower].size() != 0) starve_count[lower]++; 
            `uvm_info("VC_Arbiter", $sformatf("Arbitration winner: VC%0d (strict priority)", v), UVM_LOW)
	    foreach (starve_count[i]) begin
  $display("VC%0d starve_count = %0d", i, starve_count[i]);
end
            return;

          end
          else begin
            `uvm_info("VC_Arbiter", $sformatf("VC%0d head-of-line blocked on credit, checking lower VCs", v), UVM_HIGH)
          end

        end

      end

      // Nothing schedulable this cycle (all empty or all credit-starved)
      @(posedge TX_TL_DL.CLK);

    end

  endtask

  // Optional: call periodically from a monitor/scoreboard if you
  // want a testbench-side starvation check rather than just a
  // spec-legal "strict priority can starve low VCs" acceptance.
  function bit is_starving(vc_id_e vc, int threshold = 1000);
    return (starve_count[vc] > threshold);
  endfunction

endclass : VC_Arbiter
