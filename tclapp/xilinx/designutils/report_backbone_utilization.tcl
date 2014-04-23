package require Vivado 1.2014.1


namespace eval ::tclapp::xilinx::designutils {
    namespace export report_backbone_utilization
}

proc ::tclapp::xilinx::designutils::report_backbone_utilization {} {
	# Summary : 
	# generates a CMT BACKBONE usage report

	# Argument Usage:

	# Return Value:
	# 0
	# TCL_ERROR if an error happened

	# Categories: xilinxtclstore, designutils
	
	#CMT backbone only exists on 7-series
	set arch [get_property ARCHITECTURE [get_parts -of [current_design]]]

	if {!($arch eq "virtex7" || $arch eq "kintex7" || $arch eq "artix7")} {
	error " error - report_backbone_utilization command only supports 7-series devices."
	}
	
	# loop through CMT Backbone nodes of left and right CMT columns and collect data for get_nets -of nodes 
	set BB_node PLL_CLK_FREQ_BB0_NS
	set all_BB_nodes [get_nodes CMT_TOP_?_UPPER_T_*/PLL_CLK_FREQ_BB*_NS]
	foreach side {R L} {
		if {$side eq "R"} {set CMT_col "Left"} else {set CMT_col "Right"}
		foreach node_name [filter $all_BB_nodes NAME=~CMT_TOP_${side}_UPPER_T_*/$BB_node] {
			foreach num {3 2 1 0} {
				regsub -all "BB0" $node_name "BB${num}" node
				set node [get_nodes $node]
				set BBresource($node) [get_nets -quiet -of $node]
				set current_BB_net [get_nets -quiet -of $node]
				if {$current_BB_net != ""} {
					set source_cell [get_lib_cells -of [get_cells -of [get_pins -leaf -of [get_nets -quiet -of $node] -filter DIRECTION==OUT]]]
					set source_clock_region [lsort -unique -decreasing [get_clock_regions -of [get_cells -of [get_pins -leaf -of [get_nets -quiet -of $node] -filter DIRECTION==OUT]]]]
					set dest_cell [get_lib_cells -of [get_cells -of [get_pins -leaf -of [get_nets -quiet -of $node] -filter DIRECTION==IN]]]
					set dest_clock_region [lsort -unique -decreasing [get_clock_regions -of [get_cells -of [get_pins -leaf -of [get_nets -quiet -of $node] -filter DIRECTION==IN]]]]
					lappend BBused($current_BB_net) [lindex [get_clock_regions -of  [get_sites -of [get_tiles -of $node]]] 0]
					#need to check for CDR=BACKBONE constraint on input and output of IBUFDS  
					set IBUFDS_Ipin_net [get_nets -segments -top_net_of_hierarchical_group -quiet -of [get_pins -quiet -of [get_cells -quiet -of [get_pins -leaf -of [get_nets -quiet -of $node] -filter DIRECTION==OUT] -filter LIB_CELL=~IBUF*] -filter REF_PIN_NAME=~I]] 
					if {$IBUFDS_Ipin_net ne ""} {
						set constraint [lsort -unique [concat [get_property CLOCK_DEDICATED_ROUTE [get_nets -quiet -of $node]] [get_property CLOCK_DEDICATED_ROUTE $IBUFDS_Ipin_net]]]
					} else {
						set constraint [get_property CLOCK_DEDICATED_ROUTE [get_nets -quiet -of $node]] 
					}
					#save net info for table on Net CMT backbone Routing usage
					dict set netInfo $current_BB_net sourceCell $source_cell
					dict set netInfo $current_BB_net sourceClockRegion $source_clock_region
					dict set netInfo $current_BB_net destCell $dest_cell
					dict set netInfo $current_BB_net destClockRegion $dest_clock_region
					dict set netInfo $current_BB_net constraint $constraint
					dict set netInfo $current_BB_net BBtrack $num
					dict set netInfo $current_BB_net BBnode [file tail $node]
					dict set netInfo $current_BB_net BBused $BBused($current_BB_net)
					 
				} 
			}
		}
	}
	
	# Create a list of nets that utilize a CMT backbone resource 
	puts ""
	set net_table [::tclapp::xilinx::designutils::prettyTable create]
	$net_table header { {Index} \
						{Net} \
						{CMT Backbone Node} \
						{Source LIB_CELL} \
						{Destination LIB_CELL(s)} \
						{Source Clock Region} \
						{Destination Clock Region(s)} \
						{Clock Region Used} \
						{Clock Region Req.} \
						{CDR Constraint} \
						{CMT Backbone Route} }
	set i 1
	foreach net [dict keys $netInfo] {
		if {[llength [dict get $netInfo $net BBused]] == [llength [::tclapp::xilinx::designutils::report_backbone_usage::get_backbone_clk_regions [dict get $netInfo $net sourceClockRegion] [dict get $netInfo $net destClockRegion]]]} { 
			set status "All Backbone"
		} else {
			set status "Partial Backbone"
		}
		$net_table addrow [list $i \
								$net \
								[dict get $netInfo $net BBnode] \
								[dict get $netInfo $net sourceCell] \
								[dict get $netInfo $net destCell] \
								[dict get $netInfo $net sourceClockRegion] \
								[dict get $netInfo $net destClockRegion] \
								[dict get $netInfo $net BBused] \
								[::tclapp::xilinx::designutils::report_backbone_usage::get_backbone_clk_regions [dict get $netInfo $net sourceClockRegion] [dict get $netInfo $net destClockRegion]] \
								[dict get $netInfo $net constraint] \
								$status ]
		incr i
	}

	$net_table configure -title "Nets using CMT Backbone routing" 
	puts [$net_table print]\n
	catch {$net_table destroy}

	# Create a table that shows the CMT backbone usage
	set table [::tclapp::xilinx::designutils::prettyTable create]
	$table header { {CMT Column} {Clock Region} {BB3 BB2 BB1 BB0}}

	foreach side {R L} {
		if {$side eq "R"} {set CMT_col "Left"} else {set CMT_col "Right"}
		#need to sort the nodes from BB3 downto BB0 so list of occupied nodes can be properly assembled
		foreach node [lsort -decreasing [filter $all_BB_nodes NAME=~CMT_TOP_${side}_UPPER_T_*/PLL_CLK_FREQ_BB*_NS]] {
			set index [lsearch [dict keys $netInfo] $BBresource($node)]
			if {$index == -1} {set index "  "} else {[incr index]}
			lappend BBclockRegion${CMT_col}([lindex [get_clock_regions -of  [get_sites -of [get_tiles -of $node]]] 0]) [format {%2s} $index]
		}
		foreach clockRegion [lsort -decreasing [array names BBclockRegion${CMT_col}]] {
			$table addrow [list ${CMT_col} $clockRegion  " [join [set BBclockRegion${CMT_col}($clockRegion)] "  "]"]
		}
		$table separator
	}
  

	# Print simple table and summary
	$table configure -title "CMT Backbone Resource Utilization\n(Numbers in Backbone Column represent index\n of nets using CMT Backbone routing)" 
	puts [$table print]\n
	
	# Destroy the table objects to free memory
	catch {$table destroy}
	return 0
}
