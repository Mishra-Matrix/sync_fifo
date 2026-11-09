#!/bin/sh
# Vivado simulator. Usage (from the sim/ folder):  sh run_xsim.sh
xvlog -sv ../rtl/sync_fifo.sv ../sva/sync_fifo_sva.sv ../tb/tb_sync_fifo.sv
xelab -debug typical tb_sync_fifo -s fifo_sim
xsim fifo_sim -runall
