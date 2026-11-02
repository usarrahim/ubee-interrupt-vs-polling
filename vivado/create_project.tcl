# create_project.tcl - creates the Vivado project and the block design
#
# Batch mode:
#   vivado -mode batch -source vivado/create_project.tcl -tclargs <path to uBee clone> [project dir]
# Vivado Tcl console:
#   set argv [list <path to uBee clone>]
#   source <repo>/vivado/create_project.tcl
set repo [file dirname [file dirname [file normalize [info script]]]]
if {[llength $argv] < 1} { error "give the path of your GSTL-ITU/uBee clone" }
set ubee [file normalize [lindex $argv 0]]
if {[llength $argv] > 1} { set proj_dir [lindex $argv 1] } else { set proj_dir $repo/build/vivado }

create_project hw2 $proj_dir -part xc7a35ticsg324-1L -force
set_property ip_repo_paths [list $ubee/IP] [current_project]
update_ip_catalog
source $repo/vivado/create_bd.tcl
puts "Project ready: $proj_dir/hw2.xpr"
