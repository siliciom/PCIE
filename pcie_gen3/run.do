vlib work

vmap work work

# NUM_RC and NUM_EP are set HERE, at compile time, via +define+.
# This is the SINGLE source of truth for how many RC and EP
# instances exist in the testbench.
# Do NOT set these via vsim +plusargs - `ifdef macros are
# resolved at compile time by vlog, not at runtime by vsim.
#
# For a basic single-pair simulation use NUM_RC=1 NUM_EP=1.
# The sequencer in each test drives RC_Env[0].TX_TL_Agnt.TX_TL_Seqr.
# If NUM_RC > 1, instances RC_Env[1..N] are built and reach link-up
# but are not driven by the base test - extend run_phase to drive them.
#
# Available test names (change +UVM_TESTNAME= below):
#   Single_Mem_Wr_Rd_3DW_test    Single_Mem_Wr_Rd_4DW_test
#   Multiple_Mem_Wr_Rd_3DW_test  Multiple_Mem_Wr_Rd_4DW_test
#   B2B_Mem_Wr_Rd_3DW_test       B2B_Mem_Wr_Rd_4DW_test
#   Single_IO_Wr_Rd_3DW_test     Multiple_IO_Wr_Rd_3DW_test
#   B2B_IO_Wr_Rd_3DW_test

vlog -work work -sv +define+NUM_RC=1 +define+NUM_EP=1 ../top/Package.sv ../top/TOP.sv

set infile [open "logfile.sv" w+]

vsim work.PCIe_top +UVM_TESTNAME=Single_Mem_Wr_Rd_3DW_test +UVM_VERBOSITY=UVM_LOW -l $infile

add log -r /*

run -all
