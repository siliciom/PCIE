
`include "Package.sv"

module PCIe_top;
  `include "uvm_macros.svh"
  import uvm_pkg::*;
    
  bit CLK = 0;
  bit RESET;
  
  bit PCLK = 0;
  
  always #2 CLK = ~CLK;
  
  always #5 PCLK = ~PCLK;
  
  initial begin    
    RESET = 0;
    #20;
    RESET = 1;
  end
  
  TX_TL_DL_Interface TX_TL_DLL(CLK);
  RX_TL_DL_Interface RX_TL_DLL(CLK);
  TX_DLL_PCS_Interface TX_DLL_PCS(CLK);
  RX_DLL_PCS_Interface RX_DLL_PCS(CLK);
  pipe_tx_interface  TX_PIPE_INT(PCLK);
  pipe_rx_interface  RX_PIPE_INT(PCLK);
  phy_tx_interface      PHY_TX_INT(CLK);
  phy_rx_interface      PHY_RX_INT(CLK);
  
  assign PHY_RX_INT.RX = PHY_TX_INT.TX;
  assign PHY_TX_INT.RX = PHY_RX_INT.TX;
  
  initial begin
    uvm_config_db#(virtual TX_TL_DL_Interface)::set(null, "uvm_test_top.Env_top*", "TL_Vif", TX_TL_DLL);
    uvm_config_db#(virtual RX_TL_DL_Interface)::set(null, "uvm_test_top.Env_top*", "TL_Vif", RX_TL_DLL);
    uvm_config_db#(virtual TX_DLL_PCS_Interface)::set(null, "uvm_test_top.Env_top*", "DLL_Vif", TX_DLL_PCS);
    uvm_config_db#(virtual RX_DLL_PCS_Interface)::set(null, "uvm_test_top.Env_top*", "DLL_Vif", RX_DLL_PCS);
    uvm_config_db#(virtual pipe_tx_interface)::set(null, "uvm_test_top.Env_top*", "pipe_vif", TX_PIPE_INT);
    uvm_config_db#(virtual pipe_rx_interface)::set(null, "uvm_test_top.Env_top*", "pipe_vif", RX_PIPE_INT);
    uvm_config_db#(virtual phy_tx_interface)::set(null, "uvm_test_top.Env_top*", "phy_vif", PHY_TX_INT);
    uvm_config_db#(virtual phy_rx_interface)::set(null, "uvm_test_top.Env_top*", "phy_vif", PHY_RX_INT);
    run_test("Test");
  end

  initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0, PCIe_top);
   // #1000 $finish;
  end
  
endmodule : PCIe_top
