# Usage (from the sim/ folder):  vsim -c -do run_questa.do
vlib work
vlog -sv +acc ../rtl/sync_fifo.sv ../sva/sync_fifo_sva.sv ../tb/tb_sync_fifo.sv
vsim -assertdebug work.tb_sync_fifo
run -all
assertion report -verbose
coverage report -cvg -details
quit -f
