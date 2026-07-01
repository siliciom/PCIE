`uvm_analysis_imp_decl(_port_a)
`uvm_analysis_imp_decl(_port_b)
`uvm_analysis_imp_decl(_port_c)
`uvm_analysis_imp_decl(_port_d)

class PCIe_PMA_driver extends uvm_driver#(Sequence_item);
  `uvm_component_utils(PCIe_PMA_driver)

  env_cfg cfg;
  string  tag;

  virtual phy_tx_interface  phy_tx_vif;
  virtual pipe_tx_interface pipe_tx_vif;

  virtual phy_rx_interface  phy_rx_vif;
  virtual pipe_rx_interface pipe_rx_vif;

  uvm_analysis_imp_port_c #(Sequence_item, PCIe_PMA_driver) pma_tx_recv_mac;  // RC_MODE
  uvm_analysis_imp_port_d #(Sequence_item, PCIe_PMA_driver) pma_tx_recv_rx;   // RC_MODE

  uvm_analysis_imp_port_a #(Sequence_item, PCIe_PMA_driver) pma_rx_recv_mac;  // EP_MODE
  uvm_analysis_imp_port_b #(Sequence_item, PCIe_PMA_driver) pma_rx_recv_tx;   // EP_MODE

  uvm_event pma_tx_rx_drive;   // RC_MODE triggers, once per serialised bit
  uvm_event pma_rx_tx_drive;   // EP_MODE triggers, once per serialised bit
  uvm_event pma_rx_done;       // both RC_MODE and EP_MODE trigger this

  // RC_MODE queues
  bit [129:0] tx_data_q[$];
  bit [129:0] mac_tx_data_q[$];
  int size;
  int size_t;

  // EP_MODE queues
  bit [129:0] rx_data_q[$];
  bit [129:0] mac_rx_data_q[$];
  bit [129:0] rx_temp_data;

  bit receiver_present = 1;

  function new (string name = "PCIe_PMA_driver", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("PCIe_PMA_driver", $sformatf("env_cfg not found for %s", get_full_name()))

    tag = get_full_name();
    `uvm_info("PCIe_PMA_driver", $sformatf("[%s] Configured: mode=%s", tag, cfg.mode.name()), UVM_LOW)

    // Shared global events - same names used by pma_tx_monitor / the
    pma_tx_rx_drive = uvm_event_pool::get_global("pma_tx_rx");
    pma_rx_tx_drive = uvm_event_pool::get_global("pma_rx_tx");
    pma_rx_done     = uvm_event_pool::get_global("pma_rx_done");

    pma_tx_recv_mac = new("pma_tx_recv_mac", this);
    pma_tx_recv_rx  = new("pma_tx_recv_rx",  this);
    pma_rx_recv_mac = new("pma_rx_recv_mac", this);
    pma_rx_recv_tx  = new("pma_rx_recv_tx",  this);

    case(cfg.mode)

      RC_MODE: begin
        if(!uvm_config_db#(virtual phy_tx_interface)::get(this, "", "phy_Vif", phy_tx_vif))
          `uvm_fatal("PCIe_PMA_driver",
            $sformatf("[%s] Cannot get phy_tx_interface (phy_Vif)", tag))

        if(!uvm_config_db#(virtual pipe_tx_interface)::get(this, "", "pipe_Vif", pipe_tx_vif))
          `uvm_fatal("PCIe_PMA_driver",
            $sformatf("[%s] Cannot get pipe_tx_interface (pipe_Vif)", tag))

        `uvm_info("PCIe_PMA_driver", $sformatf("[%s] RC interfaces connected", tag), UVM_LOW)
      end

      EP_MODE: begin
        if(!uvm_config_db#(virtual phy_rx_interface)::get(this, "", "phy_Vif", phy_rx_vif))
          `uvm_fatal("PCIe_PMA_driver",
            $sformatf("[%s] Cannot get phy_rx_interface (phy_Vif)", tag))

        if(!uvm_config_db#(virtual pipe_rx_interface)::get(this, "", "pipe_Vif", pipe_rx_vif))
          `uvm_fatal("PCIe_PMA_driver",
            $sformatf("[%s] Cannot get pipe_rx_interface (pipe_Vif)", tag))

        `uvm_info("PCIe_PMA_driver", $sformatf("[%s] EP interfaces connected", tag), UVM_LOW)
      end

      default: `uvm_fatal("PCIe_PMA_driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endfunction

  function void write_port_d(Sequence_item pma_tx);
    foreach (pma_tx.tx_data_q[i])
      tx_data_q.push_back(pma_tx.tx_data_q[i]);
    `uvm_info("PMA_TX_DRV", $sformatf("[%s] tx_data_q size=%0d", tag, tx_data_q.size()), UVM_LOW)
    pma_tx.size_tx_rx = tx_data_q.size();
  endfunction

  function void write_port_c(Sequence_item pma_rx);
    foreach (pma_rx.pma_tx_data[i])
      mac_tx_data_q.push_back(pma_rx.pma_tx_data[i]);
    `uvm_info("PMA_TX_DRV", $sformatf("[%s] mac_tx_data_q size=%0d", tag, mac_tx_data_q.size()), UVM_LOW)
  endfunction

  function void write_port_a(Sequence_item pma_rx);
    foreach (pma_rx.pma_rx_data[i])
      rx_data_q.push_back(pma_rx.pma_rx_data[i]);
    `uvm_info("PMA_RX_DRV", $sformatf("[%s] port_a: rx_data_q now %0d entries", tag, rx_data_q.size()), UVM_LOW)
  endfunction

  function void write_port_b(Sequence_item pma_rx);
    foreach (pma_rx.pma_tx_data_t[i])
      mac_rx_data_q.push_back(pma_rx.pma_tx_data_t[i]);
    `uvm_info("PMA_RX_DRV", $sformatf("[%s] port_b: mac_rx_data_q %p now %0d entries", tag, mac_rx_data_q, mac_rx_data_q.size()), UVM_LOW)
    pma_rx.size_rx_tx = mac_rx_data_q.size();
  endfunction

  virtual task run_phase(uvm_phase phase);

    case(cfg.mode)

      RC_MODE: begin

        phy_tx_vif.TX <= 0;
        phy_tx_vif.RX <= 0;

        `uvm_info("PMA_TX", $sformatf("[%s] Starting receiver detection", tag), UVM_LOW)

        repeat(6) begin
          @(posedge pipe_tx_vif.PCLK);
          pipe_tx_vif.TxDetectRx = 1'b1;
        end

        @(posedge pipe_tx_vif.PCLK);
        pipe_tx_vif.PhyStatus = 1;

        if (receiver_present)
          pipe_tx_vif.RxStatus = 3'b011;
        else
          pipe_tx_vif.RxStatus = 3'b000;

        @(posedge pipe_tx_vif.PCLK);
        pma_rx_done.trigger();

        @(posedge pipe_tx_vif.PCLK);
        pipe_tx_vif.PhyStatus  = 0;
        pipe_tx_vif.RxStatus   = 3'b000;
        pipe_tx_vif.TxDetectRx = 1'b0;

        fork
          begin
            forever begin
              wait(tx_data_q.size() > 0);
              `uvm_info("PMA_TX", $sformatf("[%s] RC Started TX DATA TRANSMISSION time = %t", tag, $time), UVM_LOW)
              begin
                bit [129:0] tmp;
                size = tx_data_q.size();
                for(int i = 0; i < size; i++) begin
                  tmp = tx_data_q.pop_front();
                  for (int j = 0; j < 130; j++) begin
                    #4;
                    phy_tx_vif.TX <= tmp[j];
                    pma_tx_rx_drive.trigger();
                  end
                end
              end
              `uvm_info("PMA_TX", $sformatf("[%s] RC Completed TX DATA TRANSMISSION time = %t", tag, $time), UVM_LOW)
            end
          end

          begin
            forever begin
              wait(mac_tx_data_q.size());
              `uvm_info("PMA_TX", $sformatf("[%s] RC Started RX DATA TRANSMISSION time = %t", tag, $time), UVM_LOW)
              size_t = mac_tx_data_q.size();
              for(int i = 0; i < size_t; i++) begin
                @(posedge pipe_tx_vif.PCLK);
                pipe_tx_vif.RxData  <= mac_tx_data_q.pop_front();
                pipe_tx_vif.RxValid <= 1;
              end
              @(posedge pipe_tx_vif.PCLK);
              pipe_tx_vif.RxValid <= 0;
              `uvm_info("PMA_TX", $sformatf("[%s] RC Stopped RX DATA TRANSMISSION time = %t", tag, $time), UVM_LOW)
            end
          end
        join

      end

      EP_MODE: begin

        `uvm_info("PMA_RX", $sformatf("[%s] Starting receiver detection", tag), UVM_LOW)

        repeat(6) begin
          @(posedge pipe_rx_vif.PCLK);
          pipe_rx_vif.TxDetectRx = 1'b1;
        end

        @(posedge pipe_rx_vif.PCLK);
        pipe_rx_vif.PhyStatus = 1;

        if (receiver_present)
          pipe_rx_vif.RxStatus = 3'b011;
        else
          pipe_rx_vif.RxStatus = 3'b000;

        @(posedge pipe_rx_vif.PCLK);
        pma_rx_done.trigger();

        @(posedge pipe_rx_vif.PCLK);
        pipe_rx_vif.PhyStatus  = 0;
        pipe_rx_vif.RxStatus   = 3'b000;
        pipe_rx_vif.TxDetectRx = 1'b0;

        fork
          begin
            forever begin
              wait(mac_rx_data_q.size() > 0);
              `uvm_info("PMA_RX", $sformatf("[%s] EP Started TX DATA TRANSMISSION time = %t", tag, $time), UVM_LOW)
              size = mac_rx_data_q.size();
              for(int i = 0; i < size; i++) begin
                rx_temp_data = mac_rx_data_q.pop_front();
                for (int j = 0; j < 130; j++) begin
                  #4;
                  phy_rx_vif.TX <= rx_temp_data[j];
                  pma_rx_tx_drive.trigger();
                end
              end
              `uvm_info("PMA_RX", $sformatf("[%s] EP Stopped TX DATA TRANSMISSION time = %t", tag, $time), UVM_LOW)
            end
          end

          begin
            forever begin
              wait(rx_data_q.size() > 0);
              begin
                int burst_size;
                burst_size = rx_data_q.size();
                `uvm_info("PMA_RX", $sformatf("[%s] EP Started RX DATA TRANSMISSION time = %t", tag, $time), UVM_LOW)
                for (int i = 0; i < burst_size; i++) begin
                  @(posedge pipe_rx_vif.PCLK);
                  pipe_rx_vif.RxData  <= rx_data_q.pop_front();
                  pipe_rx_vif.RxValid <= 1;
                end
                @(posedge pipe_rx_vif.PCLK);
                pipe_rx_vif.RxValid <= 0;
                `uvm_info("PMA_RX", $sformatf("[%s] EP Stopped RX DATA TRANSMISSION time = %t", tag, $time), UVM_LOW)
              end
            end
          end
        join

      end

      default: `uvm_fatal("PCIe_PMA_driver", $sformatf("[%s] Unknown mode", tag))

    endcase

  endtask

endclass
