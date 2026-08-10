class PCIe_TL_Driver extends uvm_driver #(Sequence_item);

  `uvm_component_utils(PCIe_TL_Driver)

  env_cfg cfg;
  string  tag;
  int hdr_credit;
  int data_credit;   

  virtual TX_TL_DL_Interface TX_TL_DL;   // RC_MODE
  virtual RX_TL_DL_Interface RX_TL_DL;   // EP_MODE

  int rc_size;
  bit rc_flag;

  // CHANGED: no longer needs a direct handle to RX_PCIe_LUT at all —
  // decoupled via analysis port/imp instead.
  // (removed: RX_PCIe_LUT ep_lut;)

  FC_Manager fc_mgr;
  VC_Arbiter vc_arb;
  vc_id_e    won_vc;
  Sequence_item ep_req_q[$];
  int ep_size;
  bit ep_flag;

  // NEW: analysis imp that receives completions pushed from RX_PCIe_LUT.cpl_ap
  uvm_analysis_imp #(Sequence_item, PCIe_TL_Driver) cpl_imp;

  // NEW: internal completion queue — write() is a function and can't block/drive,
  // so it just enqueues; run_phase's forever loop drains it (same pattern the
  // LUT itself uses for req_q).
  Sequence_item ep_cpl_q[$];

  function new(string name = "PCIe_TL_Driver", uvm_component parent = null);
    super.new(name, parent);
    cpl_imp = new("cpl_imp", this);      // NEW
  endfunction

  // NEW: implements uvm_analysis_imp's write() — called by RX_PCIe_LUT.cpl_ap.write()
  function void write(Sequence_item cpl);
    ep_cpl_q.push_back(cpl);
    `uvm_info("TX_TL_Driver", $sformatf("[%s] CPL received via analysis port, queue size=%0d",
                                         tag, ep_cpl_q.size()), UVM_LOW)
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("TX_TL_Driver", $sformatf("env_cfg not found for %s", get_full_name()))

    if(!uvm_config_db #(FC_Manager)::get(this, "", "fc_mgr", fc_mgr))
      `uvm_fatal("RX_DRV","Unable to get FC Manager")

    tag = get_full_name();

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
          `uvm_fatal("TX_TL_Driver", $sformatf("[%s] Unable to access the TX_TL_DLL from config_db", tag))

        if(!uvm_config_db#(VC_Arbiter)::get(this, "", "vc_arb", vc_arb))
          `uvm_fatal("TX_TL_Driver", $sformatf("[%s] Unable to get VC_Arbiter", tag))
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
          `uvm_fatal("RX_TL_DRIVER", $sformatf("[%s] Unable to access RX TL interface", tag))

        // CHANGED: removed the uvm_config_db#(RX_PCIe_LUT)::get(...) lookup for
        // "lut_handle" — the driver no longer needs the LUT object itself,
        // only its cpl_ap connected to this driver's cpl_imp (done in the
        // parent agent's connect_phase — see notes below).
      end

      default: `uvm_fatal("TX_TL_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction : build_phase

  task rc_feeder();
    forever begin
      seq_item_port.get_next_item(req);
      `uvm_info("TX_TL_Driver",
        $sformatf("[%s] Packet pulled from sequencer: e_type=%s addr=%0h length=%0d",
          tag, req.e_type.name(), req.addr, req.length), UVM_LOW)
      req.pack_tlp();
      vc_arb.push(req);
      seq_item_port.item_done();
    end
  endtask : rc_feeder

  task rc_sender();
    forever begin
      vc_arb.get_next(req, won_vc, TX_TL_DL);
      calc_credit(req);
      rc_size = req.tlp_q.size();

      `uvm_info("TX_TL_Driver",
        $sformatf("[%s] Driving TLP on TX_TL_DL: e_type=%s vc=%s %0d DWs",
          tag, req.e_type.name(), won_vc.name(), rc_size), UVM_LOW)

      for(int i = 0; i < rc_size; i++) begin
        while(!TX_TL_DL.tl_tx_ready)
          @(posedge TX_TL_DL.CLK);
        @(posedge TX_TL_DL.CLK);

        TX_TL_DL.tl_tx_valid <= 1'b1;
        TX_TL_DL.tl_tx_data  <= req.tlp_q[i];
        TX_TL_DL.tl_tx_request_sop <= (i == 0);
        TX_TL_DL.tl_tx_request_eop <= (i == req.tlp_q.size()-1);

        `uvm_info("TX_TL_Driver",
          $sformatf("[%s] TX beat %0d/%0d data=%0h sop=%0b eop=%0b",
            tag, i, rc_size-1, req.tlp_q[i], (i==0), (i==req.tlp_q.size()-1)),
          UVM_HIGH)
      end

      fc_mgr.consume_credit(won_vc, req.pkt_type, hdr_credit, data_credit);

      @(posedge TX_TL_DL.CLK);
      TX_TL_DL.tl_tx_valid <= 0;
      TX_TL_DL.tl_tx_data  <= 0;
      TX_TL_DL.tl_tx_request_sop <= 0;
      TX_TL_DL.tl_tx_request_eop <= 0;

      `uvm_info("TX_TL_Driver",
        $sformatf("[%s] TLP drive complete: e_type=%s", tag, req.e_type.name()), UVM_LOW)
    end
  endtask : rc_sender

  task calc_credit(Sequence_item req);
    fc_mgr.calc_required_credit(req, hdr_credit, data_credit);
  endtask : calc_credit

  task ep_send_tlp(Sequence_item pkt);
    ep_size = pkt.tlp_q.size();

    `uvm_info("RX_TL_DRIVER",
      $sformatf("[%s] Driving completion TLP on RX_TL_DL: e_type=%s %0d DWs",
        tag, pkt.e_type.name(), ep_size), UVM_LOW)

    for(int i = 0; i < ep_size; i++) begin
      if(i == 0 && ep_flag == 1) begin
        pkt.count_tlp++;
        ep_flag = 0;
      end

      while(!RX_TL_DL.tl_tx_ready)
        @(posedge RX_TL_DL.CLK);
      @(posedge RX_TL_DL.CLK);

      RX_TL_DL.tl_tx_valid <= 1'b1;
      RX_TL_DL.tl_tx_data  <= pkt.tlp_q[i];
      RX_TL_DL.tl_rx_completion_sop <= (i == 0);
      RX_TL_DL.tl_rx_completion_eop <= (i == pkt.tlp_q.size()-1);
      #1;

      `uvm_info("RX_TL_DRIVER",
        $sformatf("[%s] RX CPL beat %0d/%0d data=%0h sop=%0b eop=%0b",
          tag, i, ep_size-1, pkt.tlp_q[i], (i==0), (i==pkt.tlp_q.size()-1)),
        UVM_HIGH)
    end

    repeat(10) begin
      @(posedge RX_TL_DL.CLK);
      RX_TL_DL.tl_tx_valid <= 0;
      RX_TL_DL.tl_tx_data  <= 0;
      RX_TL_DL.tl_rx_completion_sop <= 0;
      RX_TL_DL.tl_rx_completion_eop <= 0; 
    end

    `uvm_info("RX_TL_DRIVER",
      $sformatf("[%s] Completion TLP drive complete: e_type=%s", tag, pkt.e_type.name()),
      UVM_LOW)
  endtask : ep_send_tlp

  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      RC_MODE: begin
        TX_TL_DL.tl_tx_valid <= 0;
        TX_TL_DL.tl_tx_data  <= 0;
        TX_TL_DL.tl_tx_request_sop <= 0;
        TX_TL_DL.tl_tx_request_eop <= 0; 

        wait (TX_TL_DL.RESET == 1);
        drive_tx_fc_thread();

        fork
          rc_feeder();
          rc_sender();
        join
      end

      EP_MODE: begin
        Sequence_item cpl;

        RX_TL_DL.tl_tx_valid <= 0;
        RX_TL_DL.tl_tx_data  <= 0;
        RX_TL_DL.tl_rx_completion_sop <= 0;
        RX_TL_DL.tl_rx_completion_eop <= 0;

        forever begin
          drive_rx_fc_thread();

          // CHANGED: was `ep_lut.cpl_fifo.get(cpl);`
          wait(ep_cpl_q.size() > 0);
          cpl = ep_cpl_q.pop_front();

          `uvm_info("RX_TL_DRIVER",
            $sformatf("[%s] Completion popped from cpl queue: e_type=%s (queue size now=%0d)",
              tag, cpl.e_type.name(), ep_cpl_q.size()), UVM_LOW)
          ep_flag = 1;
          ep_send_tlp(cpl);
        end
      end

      default: `uvm_fatal("RX_TL_DRIVER", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask : run_phase

  task drive_tx_fc_thread();
    @(posedge TX_TL_DL.CLK);
    TX_TL_DL.fc_ph     = fc_mgr.ph_avail;
    TX_TL_DL.fc_nph    = fc_mgr.nph_avail;
    TX_TL_DL.fc_cmplh  = fc_mgr.cplh_avail;
    TX_TL_DL.fc_pd     = fc_mgr.pd_avail;
    TX_TL_DL.fc_npd    = fc_mgr.npd_avail;
    TX_TL_DL.fc_cmpld  = fc_mgr.cpld_avail;
  endtask

  task drive_rx_fc_thread();
    @(posedge RX_TL_DL.CLK);
    RX_TL_DL.fc_ph    = fc_mgr.ph_avail;
    RX_TL_DL.fc_nph   = fc_mgr.nph_avail;
    RX_TL_DL.fc_cmplh = fc_mgr.cplh_avail;
    RX_TL_DL.fc_pd    = fc_mgr.pd_avail;
    RX_TL_DL.fc_npd   = fc_mgr.npd_avail;
    RX_TL_DL.fc_cmpld = fc_mgr.cpld_avail;
  endtask
  
endclass : PCIe_TL_Driver
