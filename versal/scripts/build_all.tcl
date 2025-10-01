# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Script to build all.
#
# Build Vivado project for a specific module with a specific shell configuration
# Target and shell configuration are set through bash setup scripts.
# Module is set through justfile.
#
# Pin planning is defined here: hw/syn/vivado/xcv80_pin_assignment.tcl
# ==============================================================================================

# ------------------------------------------------------------------------------------------------------------------- #
# constants
# ------------------------------------------------------------------------------------------------------------------- #
# variables defined in setup bash or justfile
set PROJECT_DIR     $::env(PROJECT_DIR)
set XIL_PART        $::env(XILINX_PART)
set TOP_NAME        $::env(DESIGN_NAME)
set SHELL_VER       $::env(SHELL_VER)

# Local constants kept through all the build
set OUTDIR [lindex $::argv 0]

# This value must be between [1:32], therefore on main server we need a hardcoded value
# set MAX_THREADS [expr {[exec nproc] / 2}]
set MAX_THREADS 10

# This flag is used for avoiding project creation when sourcing create_shell script
set SKIP_PRJ_SHELL 1

# Because of the space between the two words CRITICAL and WARNING, use a variable to avoid confusion.
set CMD_CRIT "CRITICAL WARNING"

set STEP [lindex $::argv 1]
if { $::argc == 3 } {
    set USER_UPDATES [lindex $::argv 2]
    puts "USER_UPDATES: ${USER_UPDATES}"
}

# ------------------------------------------------------------------------------------------------------------------- #
# guardrail
# ------------------------------------------------------------------------------------------------------------------- #
# To avoid overwriting previous project
set vivado_dir $OUTDIR/$TOP_NAME

if {$STEP eq "new"} {
  if {[file isdirectory $vivado_dir]} {
    puts "ERROR: a directory already exists, exiting"
    exit 1
  }
}

# ------------------------------------------------------------------------------------------------------------------- #
# processes
# ------------------------------------------------------------------------------------------------------------------- #
proc import_all { } {
  global PROJECT_DIR
  global TOP_NAME
  global OUTDIR

  set constraints_path "$PROJECT_DIR/versal/constraints"

  # constraints -----------------------------------------------------------------------------------
  puts "importing general V80 constraints"

  import_files -fileset constrs_1 $constraints_path/general_constraints.xdc
  import_files -fileset constrs_1 -norecurse $constraints_path/xcv80_pin_assignment.xdc

  import_files -fileset utils_1   -norecurse "$constraints_path/hooks/hook_syn.pre.tcl"
  import_files -fileset utils_1   -norecurse "$constraints_path/hooks/hook_syn.post.tcl"
  import_files -fileset utils_1   -norecurse "$constraints_path/hooks/hook_opt.pre.tcl"
  import_files -fileset utils_1   -norecurse "$constraints_path/hooks/hook_opt.post.tcl"
  import_files -fileset utils_1   -norecurse "$constraints_path/hooks/hook_place.pre.tcl"
  import_files -fileset utils_1   -norecurse "$constraints_path/hooks/hook_place.post.tcl"
  import_files -fileset utils_1   -norecurse "$constraints_path/hooks/hook_route.pre.tcl"
  import_files -fileset utils_1   -norecurse "$constraints_path/hooks/hook_route.post.tcl"
  import_files -fileset utils_1   -norecurse "$constraints_path/hooks/hook_write_device_image.pre.tcl"

  set_property STEPS.SYNTH_DESIGN.TCL.PRE       [get_files *syn.pre.tcl]                [get_runs synth_1]
  set_property STEPS.SYNTH_DESIGN.TCL.POST      [get_files *syn.post.tcl]               [get_runs synth_1]
  set_property strategy Performance_ExtraTimingOpt                                   [get_runs impl_1]
  set_property STEPS.OPT_DESIGN.TCL.PRE         [get_files *opt.pre.tcl]                [get_runs impl_1]
  set_property STEPS.OPT_DESIGN.TCL.POST        [get_files *opt.post.tcl]               [get_runs impl_1]
  set_property STEPS.PLACE_DESIGN.TCL.PRE       [get_files *place.pre.tcl]              [get_runs impl_1]
  set_property STEPS.PLACE_DESIGN.TCL.POST      [get_files *place.post.tcl]             [get_runs impl_1]
  set_property STEPS.ROUTE_DESIGN.TCL.PRE       [get_files *route.pre.tcl]              [get_runs impl_1]
  set_property STEPS.ROUTE_DESIGN.TCL.POST      [get_files *route.post.tcl]             [get_runs impl_1]
  set_property STEPS.WRITE_DEVICE_IMAGE.TCL.PRE [get_files *write_device_image.pre.tcl] [get_runs impl_1]

  # set path where synthesis specific files will be generated
  # xrt_output_dir will be replaced in file_list to find these files
  # output dir is expected to be a sub-directory of PROJECT_DIR
  if { [info exists ::env(PROJECT_DIR) ] } {
      set project_dir $::env(PROJECT_DIR)
      set re "${project_dir}/*(.*)"
      if {![regexp $re ${OUTDIR}/rtl/inc fm_dummy xrt_output_dir]} {
          puts "ERROR> out_dir (1st arg: ${OUTDIR}) must be a sub-directory of PROJECT_DIR"
          exit
      }
  } else {
      puts "ERROR> env variable PROJECT_DIR must be set"
      exit
  }
  # RTL sources ---------------------------------------------------------------------------------------
  # Loading-up files from tcl dictionary
  # Retrieve EDAlize configuration and load associated files
  # -> ip_name_edalize contains:
  #   * design_top: name of the top level module
  #   * Edalize_Dict: [tcl dict with following entries]
  #     - vlog  -> list of verilog files
  #     - svlog -> list of SystemVerilog files
  #     - xdc   -> list of xdc constraints files
  source ${OUTDIR}/${TOP_NAME}_edalize.tcl

  set rtl_config $Edalize_Dict

  # Load XCI files
  if {[dict exists $rtl_config xci]&&[llength [dict get $rtl_config xci]]>0} {
    set xci [dict get $rtl_config xci]
    foreach f $xci {
      if {[file exists $f]} {
            read_ip ${f}
      } else {
          puts "Warn: required file $f not found"
      }
    }
  }

  set inc_re "(.*/rtl/inc/).*"
  set include_dir_list ""
  append include_dir_list "-include_dirs {"

  set rtl_l [list]
  set rtl_inc_l [list]

  # Load Vlog files
  if {[dict exists $rtl_config vlog]&&[llength [dict get $rtl_config vlog]]>0} {
    set vlog [dict get $rtl_config vlog]
    foreach f $vlog {
      if {[file exists $f]} {
          if {[regexp $inc_re $f fm_dummy include_dir_tmp]} {
            set include_dir [file dirname $f]
            append include_dir_list "$include_dir "
            lappend rtl_inc_l $f
          } else {
            lappend rtl_l $f
          }
      } else {
          puts "WARNING> required file $f not found"
      }
    }
  }

  # Load SVlog files
  if {[dict exists $rtl_config svlog]&&[llength [dict get $rtl_config svlog]]>0} {
    set svlog [dict get $rtl_config svlog]
    foreach f $svlog {
      if {[file exists $f]} {
          if {[regexp $inc_re $f fm_dummy include_dir_tmp]} {
            set include_dir [file dirname $f]
            append include_dir_list "$include_dir "
            lappend rtl_inc_l $f
          } else {
            lappend rtl_l $f
          }
      } else {
          puts "WARNING> required file $f not found"
      }
    }
  }

  # Load xdc constraints files
  if {[dict exists $rtl_config xdc]&&[llength [dict get $rtl_config xdc]]>0} {
    set xdc [dict get $rtl_config xdc]
    foreach f $xdc {
      if {[file exists $f] && [string match *_hier.xdc $f]} {
          import_files -fileset constrs_1 $f
      } else {
          puts "WARNING> required file $f not found, or not used"
      }
    }
  }
  # adds output dir with defines include
  append include_dir_list "}"
  puts "synthesis include_dir_list: ${include_dir_list}"

  puts "INFO> Include files : $rtl_inc_l"
  foreach f $rtl_inc_l {
    add_files $f
    set_property file_type "Verilog Header" [get_files $f]
    set_property IS_GLOBAL_INCLUDE 1 [get_files $f]
  }
  foreach f $rtl_l {
    add_files $f
  }

  puts "Added all sources and hierarchical constraints"
}

proc synthesis { } {
  global MAX_THREADS
  global OUTDIR
  global TOP_NAME
  global CMD_CRIT
  global USER_UPDATES

  # make clear what the top level is
  set_property top $TOP_NAME [current_fileset]
  update_compile_order -fileset sources_1

  set my_generics ""
  # Loop through list of user parameters
  # trying to set a parameter P
  # Define handling should be done before using declare_define.py
  foreach a $USER_UPDATES {
    puts "INFO> user_updates: $a"
    if {![regexp {([DP]+):([A-Za-z0-9_]*)=(.*)} $a fm_dummy type name val]} {
      puts "ERROR> Unsupported user updates arguments in $a. Must be <D:DEFINE_NAME=VALUE> or <P:PARAM_NAME=VALUE>"
      exit
    }
    if {$type == "P"} {
      puts "INFO> Set Parameter: $name=$val"
      lappend my_generics "$name=$val"
    }
  }
  if { $my_generics != "" } {
    set_property generic $my_generics [current_fileset]
  }


  launch_runs synth_1 -jobs $MAX_THREADS
  wait_on_runs synth_1

  write_messages -force -severity "INFO" -file $OUTDIR/${TOP_NAME}/syn_${TOP_NAME}_info.log
  write_messages -force -severity "WARNING" -file $OUTDIR/${TOP_NAME}/syn_${TOP_NAME}_warn.log
  write_messages -force -severity "{$CMD_CRIT}" -file $OUTDIR/${TOP_NAME}/syn_${TOP_NAME}_crit_warn.log
}

proc implementation { ntt_psi } {
  global MAX_THREADS
  global OUTDIR
  global TOP_NAME
  global CMD_CRIT

  # Create a script that can be sourced in hooks to transmit some variables
  set run_script [open $OUTDIR/${TOP_NAME}/uservars.tcl w]
  puts $run_script "variable ntt_psi $ntt_psi"
  close $run_script

  # Do NOT do it step by step here, without a full run from launch_rins impl_1
  # impl_1 won't be created and the status won't be up to date.
  launch_runs impl_1 -to_step write_device_image -jobs $MAX_THREADS
  wait_on_runs impl_1

  write_messages -force -severity "INFO" -file $OUTDIR/${TOP_NAME}/imp_${TOP_NAME}_info.log
  write_messages -force -severity "WARNING" -file $OUTDIR/${TOP_NAME}/imp_${TOP_NAME}_warn.log
  write_messages -force -severity "{$CMD_CRIT}" -file $OUTDIR/${TOP_NAME}/imp_${TOP_NAME}_crit_warn.log

  # Implementation has terminated, check it has completed successfully.
  # Check from AMD
  if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    common::send_msg_id {BUILD_HW-6} {ERROR} "Implementation failed"
  }

  common::send_msg_id {BUILD_HW-8} {INFO} {Done!}

  file copy -force $OUTDIR/${TOP_NAME}/prj.runs/impl_1/${TOP_NAME}_tandem1.pdi $OUTDIR/
  file copy -force $OUTDIR/${TOP_NAME}/prj.runs/impl_1/${TOP_NAME}_tandem2.pdi $OUTDIR/

}

proc get_psi {filename} {
  set f [open $filename]
  while {[gets $f line] != -1} {
    if {[regexp "NTT_CORE_PSI_32\/" $line]} {
      return 32
    } elseif {[regexp "NTT_CORE_PSI_64\/" $line]} {
      return 64
    }
  }
  return 16
}

proc main { } {
  global OUTDIR
  global TOP_NAME
  global XIL_PART
  global STEP
  global SHELL_VER
  global PROJECT_DIR
  global SKIP_PRJ_SHELL

  if {$STEP eq "new" || $STEP eq "gen"} {
    create_project prj "$OUTDIR/${TOP_NAME}" -part $XIL_PART -force
  } else {
    open_project "${OUTDIR}/${TOP_NAME}/prj.xpr"
  }

  set ntt_psi [get_psi "${OUTDIR}/${TOP_NAME}_edalize.tcl"]
  puts "NTT PSI detected: $ntt_psi"

  if {$STEP eq "new"} {
    import_all
    # create_shell.tcl needs arguments that are passed with argc and argv.
    set argv $::argv
    set argc $::argc
    set ::argv [list $ntt_psi]
    set ::argc 1
    source "$PROJECT_DIR/versal/scripts/create_shell.tcl"
    set ::argv $argv
    set ::argc $argc
    write_hw_platform -force -fixed -minimal "$OUTDIR/${SHELL_VER}.xsa"
    synthesis
    implementation $ntt_psi
  } elseif {$STEP eq "syn"} {
    reimport_files -force
    reset_run synth_1
    synthesis
    implementation $ntt_psi
  } elseif {$STEP eq "impl"} {
    reimport_files -force
    reset_run impl_1
    implementation $ntt_psi
  } elseif {$STEP eq "gen"} {
    import_all
    # create_shell.tcl needs arguments that are passed with argc and argv.
    set argv $::argv
    set argc $::argc
    set ::argv [list $ntt_psi]
    set ::argc 1
    source "$PROJECT_DIR/versal/scripts/create_shell.tcl"
    set ::argv $argv
    set ::argc $argc
    write_hw_platform -force -fixed -minimal "$OUTDIR/${SHELL_VER}.xsa"
  } else {
    puts "ERROR: unknown step have been chosen by user"
    exit 1
  }
}

main
