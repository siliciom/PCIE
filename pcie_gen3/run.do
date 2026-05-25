vlib work

vmap work work

vlog -work work  -sv  top/Package.sv  top/TOP.sv

set infile [open "logfile.sv" w+]

#vsim  -cvgperinstance -coverage  -c eth_top +UVM_TESTNAME=eth_test +UVM_VERBOSITY=UVM_LOW -l $infile
vsim  work.PCIe_top +UVM_TESTNAME=pcie_base_test +UVM_VERBOSITY=UVM_LOW -l $infile

add log -r /*

#add wave -r /eth_top/*

run -all


