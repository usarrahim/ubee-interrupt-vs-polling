# create_bd.tcl - builds the hw2_system block design (uBee_soc_0 + evt_gen_0)
# Usage (Vivado Tcl console, project open, uBee IP repository added):
#   source <repo>/vivado/create_bd.tcl
# or let vivado/create_project.tcl do everything.
set root [file dirname [file dirname [file normalize [info script]]]]

# source files
add_files -norecurse $root/hw/evt_gen.v
add_files -fileset sim_1 -norecurse $root/sim/tb_hw2.sv
update_compile_order -fileset sources_1

# block design (open and clear it if it exists, else create it)
if {[llength [get_files -quiet hw2_system.bd]] > 0} {
    open_bd_design [get_files hw2_system.bd]
    delete_bd_objs [get_bd_intf_nets -quiet *] [get_bd_nets -quiet *] \
                   [get_bd_cells -quiet *] [get_bd_ports -quiet *]
} else {
    create_bd_design hw2_system
}

# uBee SoC
create_bd_cell -type ip -vlnv uBee.org:user:uBee_soc:1.0 uBee_soc_0
set_property -dict [list \
    CONFIG.IMEM_INIT_FILE "$root/sw/hw2_imem.mem" \
    CONFIG.DMEM_INIT_FILE "$root/sw/hw2_dmem.mem" ] [get_bd_cells uBee_soc_0]

# event generator (RTL module)
create_bd_cell -type module -reference evt_gen evt_gen_0

# connections
connect_bd_intf_net [get_bd_intf_pins uBee_soc_0/M_AXI] [get_bd_intf_pins evt_gen_0/s_axi]
connect_bd_net [get_bd_pins evt_gen_0/irq_vec_o] [get_bd_pins uBee_soc_0/ext_irq_i]
make_bd_pins_external [get_bd_pins uBee_soc_0/clk_i]
make_bd_pins_external [get_bd_pins uBee_soc_0/rst_ni]
make_bd_pins_external [get_bd_pins uBee_soc_0/uart_tx_o]
make_bd_pins_external [get_bd_pins uBee_soc_0/gpio_in_i]
connect_bd_net [get_bd_ports clk_i_0]  [get_bd_pins evt_gen_0/s_axi_aclk]
connect_bd_net [get_bd_ports rst_ni_0] [get_bd_pins evt_gen_0/s_axi_aresetn]
set_property CONFIG.FREQ_HZ 100000000 [get_bd_ports clk_i_0]

# address: evt_gen at 0x6000_0000, 4K
assign_bd_address
set seg [get_bd_addr_segs uBee_soc_0/Reg/SEG_evt_gen_0_reg0]
set_property range 4K $seg
set_property offset 0x60000000 $seg

regenerate_bd_layout
validate_bd_design
save_bd_design

# wrapper and simulation settings
if {[llength [get_files -quiet hw2_system_wrapper.v]] == 0} {
    make_wrapper -files [get_files hw2_system.bd] -top -import
}
set_property top hw2_system_wrapper [current_fileset]
set_property top tb_hw2 [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "BD READY"
