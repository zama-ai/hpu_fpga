# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Procedure library
# ==============================================================================================

################################################################
# Check version
################################################################
proc check_version {scripts_vivado_version} {
  set current_vivado_version [version -short]

  if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
     puts ""
     if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
        catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

     } else {
       catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

     }

  }
  return $current_vivado_version
}


################################################################
# Check parent
################################################################
# Return parentObj if everythng is OK
proc check_parent_hier { parentCell nameHier } {
  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_base_logic() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  return $parentObj
}

# Return parentObj if everythng is OK
# If parentCell is "", return root
proc check_parent_root { parentCell } {
  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  return $parentObj
}

################################################################
# set_qos
################################################################
# return the string to set the connection within curly brackets
# args is couples : sep_rt_group GROUP_NAME or excl_group GROUP_NAME
proc set_qos {rd_bw wr_bw rd_avg_burst wr_avg_burst args} {
    # First, set defaults
    set sep_rt_group ""; set excl_group ""
    # Possibly override local variables from args:
    foreach {name val} $args {set $name $val}

    set l "read_bw \{$rd_bw\} write_bw \{$wr_bw\} read_avg_burst \{$rd_avg_burst\} write_avg_burst \{$wr_avg_burst\}"
    if { $sep_rt_group ne "" } {
        set l "$l sep_rt_group \{$sep_rt_group\}"
    }
    if { $excl_group ne "" } {
        set l "$l excl_group \{$excl_group\}"
    }
    return $l
}

proc set_axis_qos {wr_bw wr_avg_burst args} {
    # First, set defaults
    set sep_rt_group ""; set excl_group ""
    # Possibly override local variables from args:
    foreach {name val} $args {set $name $val}

    set l "write_bw \{$wr_bw\} write_avg_burst \{$wr_avg_burst\}"
    if { $sep_rt_group ne "" } {
        set l "$l sep_rt_group \{$sep_rt_group\}"
    }
    if { $excl_group ne "" } {
        set l "$l excl_group \{$excl_group\}"
    }
    return $l
}

################################################################
# set_curly_bracket
################################################################
# return the value, with curly brackets around
proc set_curly_bracket {val} {
    return "\{$val\}"
}
