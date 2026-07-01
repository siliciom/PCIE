class PCIe_TL_Driver extends uvm_driver #(Sequence_item);

  `uvm_component_utils(PCIe_TL_Driver)

  env_cfg cfg;
  string  tag;

  virtual TX_TL_DL_Interface TX_TL_DL;   // RC_MODE
  virtual RX_TL_DL_Interface RX_TL_DL;   // EP_MODE

  int rc_size;
  bit rc_flag;

  RX_PCIe_LUT ep_lut;
  Sequence_item ep_req_q[$];
  int ep_size;
  bit ep_flag;

  function new(string name = "PCIe_TL_Driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_TL_Driver", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_TL_Driver", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual TX_TL_DL_Interface)::get(this, "", "TL_Vif", TX_TL_DL))
          `uvm_fatal("TX_TL_Driver", $sformatf("[%s] Unable to access the TX_TL_DLL from config_db", tag))
        else
          `uvm_info("PCIe_TL_Driver", $sformatf("[%s] Successfully accessed the TX_TL_DLL from config_db", tag), UVM_LOW)
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual RX_TL_DL_Interface)::get(this, "", "TL_Vif", RX_TL_DL))
          `uvm_fatal("RX_TL_DRIVER", $sformatf("[%s] Unable to access RX TL interface", tag))

        if(!uvm_config_db#(RX_PCIe_LUT)::get(this, "", "lut_handle", ep_lut))
          `uvm_fatal("RX_TL_DRIVER", $sformatf("[%s] Unable to get LUT handle", tag))

        `uvm_info("PCIe_TL_Driver", $sformatf("[%s] DRIVER LUT HANDLE = %p", tag, ep_lut), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_TL_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction : build_phase

  task ep_send_tlp(Sequence_item pkt);

    `uvm_info("RX_TL_DRIVER", $sformatf("[%s] RX DRIVER SENDING COMPLETION", tag), UVM_LOW)

    ep_size = pkt.tlp_q.size();

    `uvm_info("RX_TL_DRIVER", $sformatf("[%s] RX_DRIVER_TLP[] = %p @(%0t)", tag, pkt.tlp_q, $time), UVM_LOW)

    for(int i = 0; i < ep_size; i++) begin

      if(i == 0 && ep_flag == 1) begin
        pkt.count_tlp++;
        `uvm_info("RX_TL_DRIVER", $sformatf("[%s] count_tlp %0d pkt size %0d $time = %t", tag, pkt.count_tlp, ep_size, $time), UVM_LOW)
        ep_flag = 0;
      end

      while(!RX_TL_DL.tl_tx_ready)
        @(posedge RX_TL_DL.CLK);
      @(posedge RX_TL_DL.CLK);

      RX_TL_DL.tl_tx_valid <= 1'b1;
      RX_TL_DL.tl_tx_data  <= pkt.tlp_q[i];

      `uvm_info("RX_TL_DRIVER", $sformatf("[%s] RX_DRIVER_TLP[%0d] = %08h @(%0t)", tag, i, pkt.tlp_q[i], $time), UVM_LOW)

    end

    repeat(10) begin
      @(posedge RX_TL_DL.CLK);
      RX_TL_DL.tl_tx_valid <= 1'b0;
      RX_TL_DL.tl_tx_data  <= 0;
    end

  endtask

  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    case(cfg.mode)

      //-------------------------------------------------------
      // RC_MODE: sequence-driven TLP transmit
      //   Preserved exactly as TX_TL_Driver.sv's run_phase.
      //-------------------------------------------------------
      RC_MODE: begin

        TX_TL_DL.tl_tx_valid <= 0;
        TX_TL_DL.tl_tx_data  <= 0;

        wait (TX_TL_DL.RESET == 1);

        forever begin

          seq_item_port.get_next_item(req);

          req.pack_tlp();
          rc_flag = 1;

          rc_size = req.tlp_q.size();
          `uvm_info("PCIe_TL_Driver", $sformatf("[%s] count_tlp %0d pkt size %0d", tag, req.count_tlp, rc_size), UVM_LOW)
          `uvm_info("PCIe_TL_Driver", $sformatf("[%s] RX_DRIVER_TLP[] = %p @(%0t)", tag, req.tlp_q, $time), UVM_LOW)

          for(int i = 0; i < rc_size; i++) begin

            if(i == 0 && rc_flag == 1) begin
              req.count_tx_tlp++;
              rc_flag = 0;
            end

            while(!TX_TL_DL.tl_tx_ready)
              @(posedge TX_TL_DL.CLK);
            @(posedge TX_TL_DL.CLK);

            TX_TL_DL.tl_tx_valid <= 1'b1;
            TX_TL_DL.tl_tx_data  <= req.tlp_q[i];

            `uvm_info("TX_TL_Driver", $sformatf("[%s] TL_TX_DRIVER_TLP_PACKET[%0d] = %0h @(%0t)", tag, i, TX_TL_DL.tl_tx_data, $time), UVM_LOW)

          end

          @(posedge TX_TL_DL.CLK);

          TX_TL_DL.tl_tx_valid <= 0;
          TX_TL_DL.tl_tx_data  <= 0;
          seq_item_port.item_done();

          req.print();

        end

      end

      EP_MODE: begin

        Sequence_item cpl;

        RX_TL_DL.tl_tx_valid <= 0;
        RX_TL_DL.tl_tx_data  <= 0;

        forever begin

          ep_lut.cpl_fifo.get(cpl);

          `uvm_info("RX_TL_DRIVER", $sformatf("[%s] COMPLETION RECEIVED FROM FIFO", tag), UVM_LOW)
          ep_flag = 1;
          ep_send_tlp(cpl);

        end

      end

      default: `uvm_fatal("PCIe_TL_Driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass : PCIe_TL_Driver
