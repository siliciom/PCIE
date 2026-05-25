 // Code your testbench here
// or browse Examples



 `include "TX_TL_DL_Interface.sv"
`include "RX_TL_DL_Interface.sv"
`include "TX_DL_PCS_Interface.sv"
`include "RX_DL_PCS_Interface.sv"
`include "TX_Pipe_interface.sv"
`include "RX_Pipe_interface.sv"
`include "Phy_Interface.sv"
 import uvm_pkg::*;
 `include "uvm_macros.svh"
// `include "Package.sv"
import Package::*;

module PCIe_top;

    
  bit CLK = 0;
  bit RESET;
  
  always #2 CLK = ~CLK;
  
  initial begin    
    RESET = 0;
    #10;
    RESET = 1;
  end
  
  TX_TL_DL_Interface TX_TL_DLL(CLK, RESET);
  RX_TL_DL_Interface RX_TL_DLL(CLK, RESET);
  TX_DLL_PCS_Interface TX_DLL_PCS(CLK);
  RX_DLL_PCS_Interface RX_DLL_PCS(CLK);
  pipe_tx_interface  TX_PIPE_INT(CLK);
  pipe_rx_interface  RX_PIPE_INT(CLK);
  phy_tx_interface      PHY_TX_INT();
  phy_rx_interface      PHY_RX_INT();
  
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
  end
  
endmodule : PCIe_top
  
  
  
