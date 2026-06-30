/////////////////////////////////////
//   TOP MODULE                    //
/////////////////////////////////////
`include "TX_TL_DL_Interface.sv"
`include "RX_TL_DL_Interface.sv"
`include "TX_DL_PCS_Interface.sv"
`include "RX_DL_PCS_Interface.sv"
`include "TX_Pipe_interface.sv"
`include "RX_Pipe_interface.sv"
`include "Phy_Interface.sv"
`include "pcie_top_defines.svh"
 import uvm_pkg::*;
 `include "uvm_macros.svh"

 // all the files where included in the Package
import Package::*;

module PCIe_top;


// NUM_RC - No of instance created that corresponds to the Multiple RC ENV it
// can be given using +define+NUM_RC while cpmpilation default it is one
  localparam int unsigned NUM_RC = `PCIE_NUM_RC;

// NUM_RC - No of instance created that corresponds to the Multiple EP ENV 
// can be given using +define+NUM_EP while cpmpilation default it is one
  localparam int unsigned NUM_EP = `PCIE_NUM_EP;

// Top clock generation with frequency = 250MHz
  bit CLK = 0;
  bit RESET;

  always #2 CLK = ~CLK;

  initial begin
    RESET = 0;
    #10;
    RESET = 1;
  end

  // RC-side interfaces - one set per RC instance
  TX_TL_DL_Interface    RC_TX_TL_DLL   [NUM_RC] (CLK, RESET);
  TX_DLL_PCS_Interface  RC_TX_DLL_PCS  [NUM_RC] (CLK, RESET);
  pipe_tx_interface     RC_TX_PIPE     [NUM_RC] (CLK, RESET);
  phy_tx_interface      RC_PHY_TX      [NUM_RC] ();

  // EP-side interfaces - one set per EP instance
  RX_TL_DL_Interface    EP_RX_TL_DLL   [NUM_EP] (CLK, RESET);
  RX_DLL_PCS_Interface  EP_RX_DLL_PCS  [NUM_EP] (CLK, RESET);
  pipe_rx_interface     EP_RX_PIPE     [NUM_EP] (CLK, RESET);
  phy_rx_interface      EP_PHY_RX      [NUM_EP] ();

  // NUM_PAIRED just to take minimum value of anyone gets supported 
  // it will be removed when switch comes into a place
  localparam int unsigned NUM_PAIRED = (NUM_RC <= NUM_EP) ? NUM_RC : NUM_EP;

  // In this generate block tx to rx and rx to tx connected for one RC to EP
  generate
    for(genvar i = 0; i < NUM_PAIRED; i++) begin : g_phy_loopback
      assign EP_PHY_RX[i].RX = RC_PHY_TX[i].TX;
      assign RC_PHY_TX[i].RX = EP_PHY_RX[i].TX;
    end
  endgenerate

  // Generate block executes at compile time where all the instance get
  // instantiated for rootcomplex and all config_db is set
  generate
    for(genvar i = 0; i < NUM_RC; i++) begin : g_rc_cfg

      initial begin
        string rc_name;
        rc_name = $sformatf("*.RC_Env_%0d.*", i);

        uvm_config_db#(virtual TX_TL_DL_Interface)::set(null, rc_name, "TL_Vif",   RC_TX_TL_DLL[i]);  // TL interface
        uvm_config_db#(virtual TX_DLL_PCS_Interface)::set(null, rc_name, "DLL_Vif", RC_TX_DLL_PCS[i]); // DL interface
        uvm_config_db#(virtual pipe_tx_interface)::set(null, rc_name, "pipe_Vif",  RC_TX_PIPE[i]);   // Pipe interface
        uvm_config_db#(virtual phy_tx_interface)::set(null, rc_name, "phy_Vif",    RC_PHY_TX[i]);   // Phy interface
      end

    end
  endgenerate

  // Generate block executes at compile time where all the instance get
  // instantiated for Endpoint and all config_db is set 
  generate
    for(genvar i = 0; i < NUM_EP; i++) begin : g_ep_cfg

      initial begin
        string ep_name;
        ep_name = $sformatf("*.EP_Env_%0d.*", i);

        uvm_config_db#(virtual RX_TL_DL_Interface)::set(null, ep_name, "TL_Vif",   EP_RX_TL_DLL[i]); // TL interface
        uvm_config_db#(virtual RX_DLL_PCS_Interface)::set(null, ep_name, "DLL_Vif", EP_RX_DLL_PCS[i]); //DL interface
        uvm_config_db#(virtual pipe_rx_interface)::set(null, ep_name, "pipe_Vif",  EP_RX_PIPE[i]); // Pipe interface
        uvm_config_db#(virtual phy_rx_interface)::set(null, ep_name, "phy_Vif",    EP_PHY_RX[i]);  // Phy interface
      end

    end
  endgenerate

  initial begin
    run_test("pcie_base_test");
  end


endmodule : PCIe_top
