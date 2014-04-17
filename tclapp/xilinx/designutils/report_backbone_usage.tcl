package require Vivado 1.2014.1


namespace eval ::tclapp::xilinx::designutils {
    namespace export report_backbone_usage
}

# Trick to silence the linter
eval [list namespace eval ::tclapp::xilinx::designutils::report_backbone_usage { 
} ]

proc ::tclapp::xilinx::designutils::report_backbone_usage {nets {table {false}}} {
	# Summary : 
	# reports CMT BACKBONE usage for net

	# Argument Usage:
	# nets: nets to be analyzed 
	# [table = false]: optionally print detailed summary of CMT BACKBONE usage for nets 

	# Return Value:
	# status of CMT backbone route for net.
	#  All Backbone: 		All nets are routed on CMT backbone
	#  Partial Backbone: 	Some nets are routed on CMT backbone
	#  Fabric: 			    All nets are routed on fabric
	# TCL_ERROR if an error happened

	# Categories: xilinxtclstore, designutils

	uplevel ::tclapp::xilinx::designutils::report_backbone_usage::report_backbone_usage $nets $table
	return 0
}


proc ::tclapp::xilinx::designutils::report_backbone_usage::report_backbone_usage {nets {table {false}}} {
	# Summary : 
	# reports CMT BACKBONE usage for net

	# Argument Usage:
	# nets: nets to be analyzed 
	# [table = false]: optionally print detailed summary of CMT BACKBONE usage for nets  

	# Return Value:
	# status of CMT backbone route for net.
	#  All Backbone: 		All nets are routed on CMT backbone
	#  Partial Backbone: 	Some nets are routed on CMT backbone
	#  Fabric: 			    All nets are routed on fabric
	# TCL_ERROR if an error happened

	# Categories: xilinxtclstore, designutils
	
	# CMT backbone only exists on 7-series
	set arch [get_property ARCHITECTURE [get_parts -of [current_design]]]
	if {!($arch eq "virtex7" || $arch eq "kintex7" || $arch eq "artix7")} {
	error " error - report_backbone_usage comand only supports 7-series devices."
	}
	
	if {$nets eq {}} {
	error " error - No nets to analyze.  report_backbone_usage comand expects a list of nets."
	}

	if {$table} {
		set net_table [::tclapp::xilinx::designutils::prettyTable create]
		$net_table header { {Index} {Net} {CMT Backbone Node} {Source LIB_CELL} {Destination LIB_CELL(s)} {Source Clock Region} {Destination Clock Region(s)} {BB Clock Region Used} {BB Clock Region Req.} {CDR Constraint} {CMT Backbone Route}}
	}
	# Nodes with names */PLL_CLK_FREQ_BB?_NS are backbone nodes
	set BBnodePattern PLL_CLK_FREQ_BB?_NS

	set i 1
	set overallStatus {}
	set CDR_backbone_IBUF_I_overall 0
	foreach net $nets {
		set CDR_backbone_IBUF_I 0
		# if CLOCK_DEDICATED_ROUTE=BACKBONE constraint is applied to input of IBUF*
		if {[string match IBUF* [get_lib_cells -of [get_cells -of [get_pins -leaf -of $net -filter DIRECTION==IN]]]]} {
			set CDR_backbone_IBUF_I 1
			set CDR_backbone_IBUF_I_overall 1
			set net [get_nets -quiet -of [get_pins -quiet -of [get_cells -quiet -of [get_pins -leaf -of $net -filter DIRECTION==IN] -filter LIB_CELL=~IBUF*] -filter REF_PIN_NAME=~O]]
		}
		set sourceCell [get_lib_cells -of [get_cells -of [get_pins -leaf -of $net -filter DIRECTION==OUT]]]
		set sourceClockRegion [lsort -unique -decreasing [get_clock_regions -of [get_cells -of [get_pins -leaf -of $net -filter DIRECTION==OUT]]]]
		set destCell [get_lib_cells -of [get_cells -of [get_pins -leaf -of $net -filter DIRECTION==IN]]]
		set destClockRegion [lsort -unique -decreasing [get_clock_regions -of [get_cells -of [get_pins -leaf -of $net -filter DIRECTION==IN]]]]
		#need to check for CDR=BACKBONE constraint on net of IBUFDS I pin of $net and $net 
		set IBUFDS_Ipin_net [get_nets -quiet -of [get_pins -quiet -of [get_cells -quiet -of [get_pins -leaf -of $net -filter DIRECTION==OUT] -filter LIB_CELL=~IBUF*] -filter REF_PIN_NAME=~I]] 
		if {$IBUFDS_Ipin_net ne ""} {
			set constraint [lsort -unique [concat [get_property CLOCK_DEDICATED_ROUTE $net] [get_property CLOCK_DEDICATED_ROUTE $IBUFDS_Ipin_net]]]
			if {[get_property CLOCK_DEDICATED_ROUTE $IBUFDS_Ipin_net]!=""} {
				set CDR_backbone_IBUF_I 1
				set CDR_backbone_IBUF_I_overall 1
			}
		} else {
			set constraint [get_property CLOCK_DEDICATED_ROUTE $net] 
		}
		if {$CDR_backbone_IBUF_I} {
			set constraint [concat $constraint " *"]
		}
		set BBused [lsort -unique [get_clock_regions -quiet -of  [get_sites -quiet -of [get_tiles -quiet -of [get_nodes -quiet -of $net -filter NAME=~*/${BBnodePattern}]]]]]
		set BBnode [file tail [lindex [get_nodes -quiet -of $net -filter NAME=~*/${BBnodePattern}] 0]] 
		if {[llength $BBused] == 0} {
			set status "Fabric"
		} elseif {[llength $BBused] == [llength [get_BB_clk_regions $sourceClockRegion $destClockRegion]]} { 
			set status "All Backbone"
		} else {
			set status "Partial Backbone"
		}
		if {$table} {
			$net_table addrow [list $i $net $BBnode $sourceCell $destCell $sourceClockRegion $destClockRegion $BBused [get_BB_clk_regions $sourceClockRegion $destClockRegion] $constraint $status]
		}
		incr i
		lappend overallStatus $status 
	}
	if {$table} {
		$net_table configure -title "CMT Backbone route usage for nets" 
		puts [$net_table print]
		if {$CDR_backbone_IBUF_I_overall} {
			puts " * If CLOCK_DEDICATED_ROUTE constraint was applied to fan-in net of IBUF*, CMT Backbone usage report is for fan-out net of IBUF*."
		}
		puts ""
		catch {$net_table destroy}
		
	} 
	# return overall CMT backbone route status of nets 
	# All Backbone: 		All nets are routed on CMT backbone
	# Partial Backbone: 	Some nets are routed on CMT backbone
	# Fabric: 				All nets are routed on fabric
	if {([lsearch $overallStatus "Fabric"] != -1)} {
		if {([lsearch $overallStatus "*Backbone"] != -1)} {
			set return_val "Partial Backbone"
		} else {
			set return_val "Fabric"
		}
	} else {
		if {([lsearch $overallStatus "Partial*"] != -1)} {
			set return_val "Partial Backbone"
		} else {
			set return_val "All Backbone"
		}
	}
	return $return_val
}

#------------------------------------------------------------------------
# ::tclapp::xilinx::designutils::report_backbone_usage::get_backbone_clk_regions
#------------------------------------------------------------------------
# **INTERNAL**
#------------------------------------------------------------------------
# Returns list of Clock Regions required by CMT backbone route of net 
#------------------------------------------------------------------------
proc ::tclapp::xilinx::designutils::report_backbone_usage::get_backbone_clk_regions {sourceClockRegion destClockRegion} {
  # Summary :

  # Argument Usage:

  # Return Value:

  # Categories: xilinxtclstore, designutils
  
  set max_region [lindex [lsort -decreasing [concat $sourceClockRegion $destClockRegion]] 0]
  set min_region [lindex [lsort [concat $sourceClockRegion $destClockRegion]] 0]
  
  regexp {X\d*Y(\d*)} $max_region -> max
  regexp {X\d*Y(\d*)} $min_region -> min
  regexp {X(\d*)Y\d*} $max_region -> CMT_col
  
  for {set i $max} {$i >= $min} {incr i -1} {
  	lappend clkRegionRequired "X${CMT_col}Y${i}"
  }
  return $clkRegionRequired
}

