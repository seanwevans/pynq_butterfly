# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "BATCH_PRODUCTS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FORWARD_TWIDDLE_INIT_FILE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FORWARD_TWIST_INIT_FILE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "INVERSE_SCALE_INIT_FILE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "INVERSE_TWIDDLE_INIT_FILE" -parent ${Page_0}


}

proc update_PARAM_VALUE.BATCH_PRODUCTS { PARAM_VALUE.BATCH_PRODUCTS } {
	# Procedure called to update BATCH_PRODUCTS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BATCH_PRODUCTS { PARAM_VALUE.BATCH_PRODUCTS } {
	# Procedure called to validate BATCH_PRODUCTS
	return true
}

proc update_PARAM_VALUE.FORWARD_TWIDDLE_INIT_FILE { PARAM_VALUE.FORWARD_TWIDDLE_INIT_FILE } {
	# Procedure called to update FORWARD_TWIDDLE_INIT_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FORWARD_TWIDDLE_INIT_FILE { PARAM_VALUE.FORWARD_TWIDDLE_INIT_FILE } {
	# Procedure called to validate FORWARD_TWIDDLE_INIT_FILE
	return true
}

proc update_PARAM_VALUE.FORWARD_TWIST_INIT_FILE { PARAM_VALUE.FORWARD_TWIST_INIT_FILE } {
	# Procedure called to update FORWARD_TWIST_INIT_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FORWARD_TWIST_INIT_FILE { PARAM_VALUE.FORWARD_TWIST_INIT_FILE } {
	# Procedure called to validate FORWARD_TWIST_INIT_FILE
	return true
}

proc update_PARAM_VALUE.INVERSE_SCALE_INIT_FILE { PARAM_VALUE.INVERSE_SCALE_INIT_FILE } {
	# Procedure called to update INVERSE_SCALE_INIT_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.INVERSE_SCALE_INIT_FILE { PARAM_VALUE.INVERSE_SCALE_INIT_FILE } {
	# Procedure called to validate INVERSE_SCALE_INIT_FILE
	return true
}

proc update_PARAM_VALUE.INVERSE_TWIDDLE_INIT_FILE { PARAM_VALUE.INVERSE_TWIDDLE_INIT_FILE } {
	# Procedure called to update INVERSE_TWIDDLE_INIT_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.INVERSE_TWIDDLE_INIT_FILE { PARAM_VALUE.INVERSE_TWIDDLE_INIT_FILE } {
	# Procedure called to validate INVERSE_TWIDDLE_INIT_FILE
	return true
}


proc update_MODELPARAM_VALUE.BATCH_PRODUCTS { MODELPARAM_VALUE.BATCH_PRODUCTS PARAM_VALUE.BATCH_PRODUCTS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BATCH_PRODUCTS}] ${MODELPARAM_VALUE.BATCH_PRODUCTS}
}

proc update_MODELPARAM_VALUE.FORWARD_TWIST_INIT_FILE { MODELPARAM_VALUE.FORWARD_TWIST_INIT_FILE PARAM_VALUE.FORWARD_TWIST_INIT_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FORWARD_TWIST_INIT_FILE}] ${MODELPARAM_VALUE.FORWARD_TWIST_INIT_FILE}
}

proc update_MODELPARAM_VALUE.FORWARD_TWIDDLE_INIT_FILE { MODELPARAM_VALUE.FORWARD_TWIDDLE_INIT_FILE PARAM_VALUE.FORWARD_TWIDDLE_INIT_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FORWARD_TWIDDLE_INIT_FILE}] ${MODELPARAM_VALUE.FORWARD_TWIDDLE_INIT_FILE}
}

proc update_MODELPARAM_VALUE.INVERSE_TWIDDLE_INIT_FILE { MODELPARAM_VALUE.INVERSE_TWIDDLE_INIT_FILE PARAM_VALUE.INVERSE_TWIDDLE_INIT_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.INVERSE_TWIDDLE_INIT_FILE}] ${MODELPARAM_VALUE.INVERSE_TWIDDLE_INIT_FILE}
}

proc update_MODELPARAM_VALUE.INVERSE_SCALE_INIT_FILE { MODELPARAM_VALUE.INVERSE_SCALE_INIT_FILE PARAM_VALUE.INVERSE_SCALE_INIT_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.INVERSE_SCALE_INIT_FILE}] ${MODELPARAM_VALUE.INVERSE_SCALE_INIT_FILE}
}

