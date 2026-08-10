interface phy_tx_interface #(parameter int unsigned NUM_LANES = `PCIE_NUM_LANES) ();

  // Per-lane serial bit stream (Option A: PCIe_PMA_driver drives an
  // identical bit-serial stream onto every active lane; this is a
  // genuine per-lane physical signal, not a mirrored/derived one -
  // each lane has its own physical wire in real PCIe).
  logic [NUM_LANES-1:0]TX ;  // Transmitting serial data to EP
  logic [NUM_LANES-1:0]RX ;  // Receiving serial data from RC

endinterface

interface phy_rx_interface #(parameter int unsigned NUM_LANES = `PCIE_NUM_LANES) ();

  logic [NUM_LANES-1:0]TX;  // Transmitting serial data to EP
  logic [NUM_LANES-1:0]RX;  // Receiving serial data from RC

endinterface
