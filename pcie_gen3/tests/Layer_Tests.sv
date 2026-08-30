//=====================================================================
// Layer_Tests.sv
//
//   layer_base_test - base for tests that inject stimulus directly at
//   the DLL / MAC / PMA layer. See docs/LAYERED_STIMULUS_PLAN.md.
//
//   A derived test:
//     - sets `stim_layer` (and optionally wait_link_up / do_enum /
//       inject_on_ep) in its constructor or an overridden pre-build
//     - in run_phase, starts a pcie_<layer>_base_seq on the matching
//       sequencer
//=====================================================================

class layer_base_test extends pcie_base_test;
  `uvm_component_utils(layer_base_test)

  // ---- knobs (set by derived test before build_phase runs) ----
  stim_layer_e stim_layer   = STIM_DLL;
  bit          wait_link_up = 1;   // DLL tests: keep 1. MAC/PMA-training tests: 0.
  bit          do_enum      = 0;   // run enumeration after link-up
  bit          inject_on_ep = 0;   // 0 = inject on RC (toward EP), 1 = inject on EP (toward RC)

  function new(string name = "layer_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);   // creates rc_cfg[]/ep_cfg[] and the envs
    // Propagate stim_layer to whichever side we inject on. The driver
    // reads cfg.stim_layer in run_phase, so setting it here (still in
    // the test's build_phase, on the shared handle) is in time.
    if (inject_on_ep)
      foreach (ep_cfg[i]) ep_cfg[i].stim_layer = stim_layer;
    else
      foreach (rc_cfg[i]) rc_cfg[i].stim_layer = stim_layer;

    `uvm_info("LAYER_TEST",
      $sformatf("stim_layer=%s  side=%s  wait_link_up=%0b  do_enum=%0b",
                stim_layer.name(), inject_on_ep ? "EP" : "RC", wait_link_up, do_enum),
      UVM_NONE)
  endfunction

  // Cannot call super.run_phase() - it unconditionally waits for
  // DL_ACTIVE on both sides and then enumerates.
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    if (wait_link_up) begin
      `uvm_info("LAYER_TEST", "waiting for DL_ACTIVE (both sides)", UVM_LOW)
      DL_up_env_rx.wait_ptrigger();
      DL_up_env.wait_ptrigger();
      `uvm_info("LAYER_TEST", "DL_ACTIVE reached", UVM_LOW)
    end
    if (do_enum) do_enumeration();

    body(phase);   // derived test does its injection here

    phase.drop_objection(this);
  endtask

  // Derived tests override this.
  virtual task body(uvm_phase phase);
    `uvm_warning("LAYER_TEST", "layer_base_test::body not overridden - nothing injected")
  endtask

  // Convenience accessors for the layer sequencers on the injecting side.
  function uvm_sequencer_base dll_seqr(int i = 0);
    return inject_on_ep ? EP_Env[i].PCIe_DLL_Agnt.PCIe_DLL_Seqr
                        : RC_Env[i].PCIe_DLL_Agnt.PCIe_DLL_Seqr;
  endfunction
  function uvm_sequencer_base mac_seqr(int i = 0);
    return inject_on_ep ? EP_Env[i].TX_MAC_Agnt.seqr
                        : RC_Env[i].TX_MAC_Agnt.seqr;
  endfunction
  function uvm_sequencer_base pma_seqr(int i = 0);
    return inject_on_ep ? EP_Env[i].TX_PMA_Agnt.PCIe_PMA_seqr
                        : RC_Env[i].TX_PMA_Agnt.PCIe_PMA_seqr;
  endfunction

endclass : layer_base_test


//---------------------------------------------------------------------
// Phase-3 smoke tests: inject the SAME memory write at TL / DLL / MAC
// and confirm the EP receives an identical TLP each way.
//---------------------------------------------------------------------

// DLL: inject a bare 3DW MEM_WR; DLL driver adds seq # + LCRC.
class layer_dll_memwr_smoke_test extends layer_base_test;
  `uvm_component_utils(layer_dll_memwr_smoke_test)
  function new(string name = "layer_dll_memwr_smoke_test", uvm_component parent = null);
    super.new(name, parent);
    stim_layer   = STIM_DLL;
    wait_link_up = 1;
    do_enum      = 1;      // so the EP has BARs and answers with a real completion
  endfunction

  task body(uvm_phase phase);
    pcie_dll_base_seq seq;
    Sequence_item     tlp;
    bit [63:0]        a = bar_base[0] + 64'h40;
    seq = pcie_dll_base_seq::type_id::create("seq");
    tlp = Sequence_item::type_id::create("tlp");
    assert(tlp.randomize() with {
      e_type   == MEM_WR;
      e_fmt    == FMT_3DW_DATA;
      addr     == a;
      length   == 4;
      td       == 1;
      tc       == 0;
      tag      == 0;
      payload.size() == 4;
    });
    seq.tlp = tlp;
    seq.start( dll_seqr() );
    #200000;
  endtask
endclass


// MAC: inject a fully framed 3DW MEM_WR (seq # + LCRC already present).
class layer_mac_memwr_smoke_test extends layer_base_test;
  `uvm_component_utils(layer_mac_memwr_smoke_test)
  function new(string name = "layer_mac_memwr_smoke_test", uvm_component parent = null);
    super.new(name, parent);
    stim_layer   = STIM_MAC;
    wait_link_up = 1;
    do_enum      = 1;
  endfunction

  task body(uvm_phase phase);
    pcie_mac_base_seq seq;
    Sequence_item     tlp;
    bit [63:0] a = bar_base[0] + 64'h50;
    seq = pcie_mac_base_seq::type_id::create("seq");
    tlp = Sequence_item::type_id::create("tlp");
    assert(tlp.randomize() with {
      e_type   == MEM_WR;
      e_fmt    == FMT_3DW_DATA;
      addr     == a;
      length   == 4;
      td       == 1;
      tc       == 0;
      tag      == 0;
      payload.size() == 4;
    });
    seq.tlp    = tlp;
    seq.seq_no = 12'h001;
    seq.start( mac_seqr() );
    #200000;
  endtask
endclass
