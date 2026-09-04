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


     FC_Manager fc_mgr;
     VC_Arbiter vc_arb;
     vc_id_e    won_vc;
     Sequence_item ep_req_q[$];
     int ep_size;
     bit ep_flag;

     uvm_analysis_imp #(Sequence_item, PCIe_TL_Driver) cpl_imp;

     Sequence_item ep_cpl_q[$];

     function new(string name = "PCIe_TL_Driver", uvm_component parent = null);
          super.new(name, parent);
          cpl_imp = new("cpl_imp", this);  // NEW
     endfunction

     function void write(Sequence_item cpl);
          ep_cpl_q.push_back(cpl);
          `uvm_info("TX_TL_Driver", $sformatf(
                    "[%s] CPL received via analysis port, queue size=%0d", tag, ep_cpl_q.size()),
                    UVM_LOW)
     endfunction

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);

          if (!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
               `uvm_fatal("TX_TL_Driver", $sformatf("env_cfg not found for %s", get_full_name()))

          if (!uvm_config_db#(FC_Manager)::get(this, "", "fc_mgr", fc_mgr))
               `uvm_fatal("RX_DRV", "Unable to get FC Manager")

          tag = get_full_name();

          case (cfg.mode)

               RC_MODE: begin
                    if (!uvm_config_db#(virtual TX_TL_DL_Interface)::get(
                            this, "", "TL_Vif", TX_TL_DL
                        ))
                         `uvm_fatal("TX_TL_Driver", $sformatf(
                                    "[%s] Unable to access the TX_TL_DLL from config_db", tag))

                    if (!uvm_config_db#(VC_Arbiter)::get(this, "", "vc_arb", vc_arb))
                         `uvm_fatal("TX_TL_Driver", $sformatf("[%s] Unable to get VC_Arbiter", tag))
               end

               EP_MODE: begin
                    if (!uvm_config_db#(virtual RX_TL_DL_Interface)::get(
                            this, "", "TL_Vif", RX_TL_DL
                        ))
                         `uvm_fatal("RX_TL_DRIVER", $sformatf(
                                    "[%s] Unable to access RX TL interface", tag))

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

               if (!TX_TL_DL.dl_up) @(posedge TX_TL_DL.CLK iff TX_TL_DL.dl_up);

               for (int i = 0; i < rc_size; i++) begin
                    while (!TX_TL_DL.tl_tx_ready) @(posedge TX_TL_DL.CLK);
                    @(posedge TX_TL_DL.CLK);

                    TX_TL_DL.tl_tx_valid <= 1'b1;
                    TX_TL_DL.tl_tx_data <= req.tlp_q[i];
                    TX_TL_DL.tl_tx_request_sop <= (i == 0);
                    TX_TL_DL.tl_tx_request_eop <= (i == req.tlp_q.size() - 1);
               end

               fc_mgr.consume_credit(won_vc, req.pkt_type, hdr_credit, data_credit);

               @(posedge TX_TL_DL.CLK);
               TX_TL_DL.tl_tx_valid <= 0;
               TX_TL_DL.tl_tx_data <= 0;
               TX_TL_DL.tl_tx_request_sop <= 0;
               TX_TL_DL.tl_tx_request_eop <= 0;
          end
     endtask : rc_sender

     task calc_credit(Sequence_item req);
          fc_mgr.calc_required_credit(req, hdr_credit, data_credit);
     endtask : calc_credit

     task ep_send_tlp(Sequence_item pkt);

          if (!RX_TL_DL.dl_up) @(posedge RX_TL_DL.CLK iff RX_TL_DL.dl_up);

          ep_size = pkt.tlp_q.size();

          for (int i = 0; i < ep_size; i++) begin
               if (i == 0 && ep_flag == 1) begin
                    pkt.count_tlp++;
                    ep_flag = 0;
               end

               while (!RX_TL_DL.tl_tx_ready) @(posedge RX_TL_DL.CLK);
               @(posedge RX_TL_DL.CLK);

               RX_TL_DL.tl_tx_valid <= 1'b1;
               RX_TL_DL.tl_tx_data <= pkt.tlp_q[i];
               RX_TL_DL.tl_rx_completion_sop <= (i == 0);
               RX_TL_DL.tl_rx_completion_eop <= (i == pkt.tlp_q.size() - 1);

               #1;
          end

          @(posedge RX_TL_DL.CLK);
          RX_TL_DL.tl_tx_valid <= 0;
          RX_TL_DL.tl_tx_data <= 0;
          RX_TL_DL.tl_rx_completion_sop <= 0;
          RX_TL_DL.tl_rx_completion_eop <= 0;

     endtask : ep_send_tlp

     task run_phase(uvm_phase phase);

          super.run_phase(phase);

          case (cfg.mode)

               RC_MODE: begin
                    TX_TL_DL.tl_tx_valid <= 0;
                    TX_TL_DL.tl_tx_data <= 0;
                    TX_TL_DL.tl_tx_request_sop <= 0;
                    TX_TL_DL.tl_tx_request_eop <= 0;

                    wait (TX_TL_DL.RESET == 1);

                    fork
                         drive_tx_fc_thread();
                         rc_feeder();
                         rc_sender();
                    join
               end

               EP_MODE: begin
                    Sequence_item cpl;

                    RX_TL_DL.tl_tx_valid <= 0;
                    RX_TL_DL.tl_tx_data <= 0;
                    RX_TL_DL.tl_rx_completion_sop <= 0;
                    RX_TL_DL.tl_rx_completion_eop <= 0;
                    fork
                         drive_rx_fc_thread();

                         forever begin
                              wait (ep_cpl_q.size() > 0);
                              cpl = ep_cpl_q.pop_front();

                              `uvm_info("RX_TL_DRIVER", $sformatf(
                                        "[%s] COMPLETION RECEIVED FROM QUEUE", tag), UVM_LOW)
                              ep_flag = 1;
                              ep_send_tlp(cpl);
                         end
                    join
               end

               default: `uvm_fatal("RX_TL_DRIVER", $sformatf("[%s] Unknown mode", tag))

          endcase

     endtask

     task drive_tx_fc_thread();

          @(posedge TX_TL_DL.CLK);

          TX_TL_DL.fc_ph              <= fc_mgr.ph_avail;
          TX_TL_DL.fc_nph             <= fc_mgr.nph_avail;
          TX_TL_DL.fc_cmplh           <= fc_mgr.cplh_avail;
          TX_TL_DL.fc_pd              <= fc_mgr.pd_avail;
          TX_TL_DL.fc_npd             <= fc_mgr.npd_avail;
          TX_TL_DL.fc_cmpld           <= fc_mgr.cpld_avail;
          TX_TL_DL.rc_fc_update_valid <= 1'b0;

          forever begin

               fc_mgr.fc_update_ev.wait_trigger();

               @(posedge TX_TL_DL.CLK);
               TX_TL_DL.fc_ph              <= fc_mgr.ph_avail;
               TX_TL_DL.fc_nph             <= fc_mgr.nph_avail;
               TX_TL_DL.fc_cmplh           <= fc_mgr.cplh_avail;
               TX_TL_DL.fc_pd              <= fc_mgr.pd_avail;
               TX_TL_DL.fc_npd             <= fc_mgr.npd_avail;
               TX_TL_DL.fc_cmpld           <= fc_mgr.cpld_avail;
               // NEW: tag which VC actually changed, so the DLL layer sends an
               // UPDATEFC DLLP carrying THIS vc's *current* (already decremented)
               // credit values - not a stale/initial snapshot.
               TX_TL_DL.rc_fc_update_vc    <= fc_mgr.last_updated_vc;
               TX_TL_DL.rc_fc_update_valid <= 1'b1;

               @(posedge TX_TL_DL.CLK);
               TX_TL_DL.rc_fc_update_valid <= 1'b0;

          end

     endtask

     task drive_rx_fc_thread();

          @(posedge RX_TL_DL.CLK);

          RX_TL_DL.fc_ph    <= fc_mgr.ph_avail;
          RX_TL_DL.fc_nph   <= fc_mgr.nph_avail;
          RX_TL_DL.fc_cmplh <= fc_mgr.cplh_avail;
          RX_TL_DL.fc_pd    <= fc_mgr.pd_avail;
          RX_TL_DL.fc_npd   <= fc_mgr.npd_avail;
          RX_TL_DL.fc_cmpld <= fc_mgr.cpld_avail;
          RX_TL_DL.ep_fc_update_valid <= 1'b0;

          forever begin

               fc_mgr.fc_update_ev.wait_trigger();

               @(posedge RX_TL_DL.CLK);
               RX_TL_DL.fc_ph    <= fc_mgr.ph_return;
               RX_TL_DL.fc_nph   <= fc_mgr.nph_return;
               RX_TL_DL.fc_cmplh <= fc_mgr.cplh_return;
               RX_TL_DL.fc_pd    <= fc_mgr.pd_return;
               RX_TL_DL.fc_npd   <= fc_mgr.npd_return;
               RX_TL_DL.fc_cmpld <= fc_mgr.cpld_return;
               // NEW: tag which VC actually changed, so the DLL layer sends an
               // UPDATEFC DLLP carrying THIS vc's *current* (already decremented)
               // credit values - not a stale/initial snapshot.
               RX_TL_DL.ep_fc_update_vc    <= fc_mgr.last_updated_vc;
               RX_TL_DL.ep_fc_update_valid <= 1'b1;

               @(posedge RX_TL_DL.CLK);
               RX_TL_DL.ep_fc_update_valid <= 1'b0;

          end

     endtask

endclass : PCIe_TL_Driver


