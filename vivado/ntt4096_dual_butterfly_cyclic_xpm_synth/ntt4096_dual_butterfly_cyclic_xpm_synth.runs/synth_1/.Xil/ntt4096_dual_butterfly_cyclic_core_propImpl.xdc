set_property SRC_FILE_INFO {cfile:F:/Xilinx/Vivado/2024.1/data/ip/xpm/xpm_memory/tcl/xpm_memory_xdc.tcl rfile:../../../../../../../Xilinx/Vivado/2024.1/data/ip/xpm/xpm_memory/tcl/xpm_memory_xdc.tcl id:1 order:LATE scoped_inst:profile_memory/profile_memory unmanaged:yes} [current_design]
current_instance profile_memory/profile_memory
set_property src_info {type:SCOPED_XDC file:1 line:55 export:INPUT save:NONE read:READ} [current_design]
set my_var [get_property dram_emb_xdc [get_cells -quiet -hier -filter {PRIMITIVE_SUBGROUP==LUTRAM || PRIMITIVE_SUBGROUP==dram || PRIMITIVE_SUBGROUP==uram || PRIMITIVE_SUBGROUP==BRAM}]]
