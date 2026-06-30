`ifndef PCIE_DEFINES_SVH
`define PCIE_DEFINES_SVH

`ifndef NUM_RC
  `define NUM_RC 1
`endif
`ifndef NUM_EP
  `define NUM_EP 1
`endif

// Alias macros - single definition point
`define PCIE_NUM_RC `NUM_RC
`define PCIE_NUM_EP `NUM_EP

`endif
