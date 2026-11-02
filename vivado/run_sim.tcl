# run_sim.tcl - runs the 19 experiments of sim/tb_hw2.sv in XSim (about 35 minutes)
# Vivado Tcl console (project open):  source <repo>/vivado/run_sim.tcl
# The UART output is written to <project>/hw2.sim/sim_1/behav/xsim/sim_log.txt
launch_simulation
set t0 [clock seconds]
run all
puts "simulation finished in [expr {[clock seconds] - $t0}] s"
