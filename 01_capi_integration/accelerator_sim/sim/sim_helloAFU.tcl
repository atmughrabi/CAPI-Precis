# recompile
proc r  {} {

  global algorithm
  # compile SystemVerilog files

  # compile libs
  echo "Compiling libs"


    vlog -quiet ../../accelerator_rtl/cu_control/cu_$algorithm/capi.sv
    vlog -quiet ../../accelerator_rtl/cu_control/cu_$algorithm/shift_register.sv
    vlog -quiet ../../accelerator_rtl/cu_control/cu_$algorithm/mmio.sv
    vlog -quiet ../../accelerator_rtl/cu_control/cu_$algorithm/parity_workelement.sv
    vlog -quiet ../../accelerator_rtl/cu_control/cu_$algorithm/parity_afu.sv


  echo "Compiling RTL AFU"
  vlog -quiet ../../accelerator_rtl/cu_control/cu_$algorithm/afu.sv

  # compile top level
  echo "Compiling top level"
  # vlog -quiet       pslse/afu_driver/verilog/top.v
  vlog -quiet -sv +define+PSL8=PSL8 ../../pslse/afu_driver/verilog/top.v

}

# simulate
proc c {} {
  # vsim -t ns -novopt -c -pli pslse/afu_driver/src/veriuser.sl +nowarnTSCALE work.top
  # vsim -t ns -L work -L work_lib -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L stratixv_ver -L stratixv_hssi_ver -L stratixv_pcie_hip_ver -novopt  -voptargs=+acc=npr -c -sv_lib ../../pslse/afu_driver/src/libdpi +nowarnTSCALE work.top
  vsim -t ns -novopt  -voptargs=+acc=npr -c -sv_lib ../../pslse/afu_driver/src/libdpi +nowarnTSCALE work.top
  view wave
  radix h
  log * -r
  # do wave.do
  do watch_job_interface.do
  do watch_mmio_interface.do
  do watch_command_interface.do
  do watch_buffer_interface.do
  do watch_response_interface.do

  view structure
  view signals
  view wave
  run -all
  # run 40
}

# shortcut for recompilation + simulation
proc rc {} {
  r
  c
}

# init libs
vlib work
vmap work work

# automatically recompile on first call
r
