#************************************************#
# ****  Pointwise GLF2 file - Tue Dec 21 2011    #
# ****  Remove Unspecified Overlapping Domains   #
#************************************************#

#************************************************#
# ****  Major issues/bugs associated with PW:    #
# ****  1. Domains with pole edges do not merge  #
# ****     properly.                             #
#************************************************#

#************************************************#
# ****  Paramerters (1):                         #
# **** 1. toler -  Tolerance used for merging    #
# ****    connectors (default = 0.0001)          #
          global  toler
          set toler 0.0001
#************************************************#
  

package require PWI_Glyph 2

# **** Beginning of SplitDom procedure
proc SplitDom { dom edge IJMinMax} {
  global Split
  set Split 0
# **** Only split edges with more than one connector
  set numcon [$edge getConnectorCount]
  if { $numcon > 1} {
    puts "Splitting $dom, $edge"

    set cntt [expr +1]

# **** Get second point on current edge on the domain
# **** Depends on edge type
      set IJ0 [lindex [$dom getDimensions] 0]
      set IJ1 [lindex [$dom getDimensions] 1]
    if {$IJMinMax == "IMinimum"} {
      set dimtt [expr {($IJ0) + 1}]
      set xyz2 [$dom getXYZ $dimtt]
    } elseif { $IJMinMax == "IMaximum"} {
      set dimtt [expr {($IJ0)*2}]
      set xyz2 [$dom getXYZ $dimtt]
    } elseif { $IJMinMax == "JMinimum"} {
      set dimtt [expr {($IJ0)*(0) + 2}]
      set xyz2 [$dom getXYZ $dimtt]
    } elseif { $IJMinMax == "JMaximum"} {
      set dimtt [expr {($IJ0)*($IJ1-1) + 2}]
      set xyz2 [$dom getXYZ $dimtt]
    }

# **** Get second point on first connector 
# **** (depends on connector orientation)
      set conn [$edge getConnector $cntt]
      set conndir [$edge getConnectorOrientation $cntt]
      if {$conndir == "Same"} {
      set xyz1 [$conn getXYZ  2]
      } else {
      set dim [$conn getDimension]
      set dimtt [expr {$dim -1}]
      set xyz1 [$conn getXYZ  $dimtt]
      }

# **** Compare the two points to determin direction of connector wrt. edge
      if { [lindex $xyz1 0] == [lindex $xyz2 0] && [lindex $xyz1 1] == [lindex $xyz2 1] && [lindex $xyz1 2] == [lindex $xyz2 2]}   {
      set dir "Same"
      set dimt [expr +1]
      } else {
      set dir "Opposite"
      set dimt [$edge getDimension]
      }
# **** Set first index of split list "dims 
       set dims $dimt

# **** Build up split list "dims"
      while { $cntt < $numcon } {
      set conn [$edge getConnector $cntt]
      set dim2 [$conn getDimension]

      if { $dir == "Opposite" } {
        set dimt [expr {$dimt - $dim2 +1}]
      } else { 
        set dimt [expr {$dimt + $dim2 -1}]
      }

      set dims [linsert $dims end $dimt]
      set cntt [expr { $cntt + 1 }]
    }

# **** Split current domain given split list
# **** Depends on edge type
    if {$IJMinMax == "IMinimum"} {
      $dom split -J $dims
    } elseif { $IJMinMax == "IMaximum"} {
      $dom split -J $dims
    } elseif { $IJMinMax == "JMinimum"} {
      $dom split -I $dims
    } elseif { $IJMinMax == "JMaximum"} {
      $dom split -I $dims
    }
    set Split 1
  }
  return $Split
}
# **** End of SplitDom  procedure


# **** Beginning of getoverlapdoms procedure

proc getoverlapdoms {} {
# **** Get "Unspecified" overlapping domains
# **** This is useful for not splitting patches,
# **** patches, singular domains
  global doms
  global domnames
  set doms ""
  set domnames ""
  foreach bcName [pw::BoundaryCondition getNames] {
#    puts "bcName: $bcName"
    
    set bc [pw::BoundaryCondition getByName $bcName]
    set bcType [$bc getPhysicalType]
    if [string equal -nocase $bcType "Unspecified"] {
      foreach entity [$bc getEntities] {
        set edge1 [$entity getEdge 1]
        set edge2 [$entity getEdge 2]
        set edge3 [$entity getEdge 3]
        set edge4 [$entity getEdge 4]
        set edges [list $edge1 $edge2 $edge3 $edge4] 
        set doverlap [pw::DomainStructured getOverlappingDomains $edges]
        set lnum [llength $doverlap]
#        puts "[$entity getName] $lnum"
#        if {$lnum > 1} {
          set doms [linsert $doms end $entity]
          set domnames [linsert $domnames end [$entity getName]]
#        }
      }
    }
  }
return doms
}
# **** End of getoverlapdoms  procedure

# **** Beginning of getoverlapdoms2 procedure

proc getoverlapdoms2 {} {
# **** Get "Unspecified" overlapping domains
# **** This is useful for not splitting patches,
# **** patches, singular domains
  global domnames
  set domnames ""
  foreach bcName [pw::BoundaryCondition getNames] {
    set bc [pw::BoundaryCondition getByName $bcName]
    set bcType [$bc getPhysicalType]
      foreach entity [$bc getEntities] {
        set edge1 [$entity getEdge 1]
        set edge2 [$entity getEdge 2]
        set edge3 [$entity getEdge 3]
        set edge4 [$entity getEdge 4]
        set edges [list $edge1 $edge2 $edge3 $edge4] 
        set doverlap [pw::DomainStructured getOverlappingDomains $edges]
        set lnum [llength $doverlap]
        if {$lnum > 1} {
          set domnames [linsert $domnames end [$entity getName]]
        }
      }
  }
return doms
}
# **** End of getoverlapdoms2  procedure

# **** Beginning of mergecons procedure
proc mergecons {} {
  global  toler
puts "Merging"
set _TMP(mode_10) [pw::Application begin Merge]
$_TMP(mode_10) mergeConnectors -exclude None -tolerance $toler
$_TMP(mode_10) end
unset _TMP(mode_10)
}

# **** End of mergecons procedure

# **** Beginning of main section
  global  toler


set madeSplit 1

# ****  Keep looping over domains until no 
# ****  splits have occured in the previous loop
set pss [expr 0]
puts "Begin Splitting"
while { $madeSplit == 1 } {

  set pss [expr $pss +1]
  puts "Pass: $pss"

  mergecons

  set madeSplit 0

  getoverlapdoms

# **** Loop through "Unspecified" overlapping domains
  foreach dom $doms { 

# ***   
# ****  Check each edge for multiple connectors and split
# ***   

# ************   Edge 1
    set IJMinMax "IMinimum"
    set edge [$dom getEdge $IJMinMax]
    if { [$edge getXYZ 2] == [$edge getXYZ [$edge getDimension]] } {
    set numcon [$edge getConnectorCount]
    set cntt [expr +1]
    puts "Skipping Pole Edge: $edge with connectors"
    set conn [$edge getConnector $cntt]
    while { $cntt <= $numcon } {
    puts "$cntt [[$edge getConnector $cntt] getName]"
      set cntt [expr { $cntt + 1 }]
    }
    } else {

    if { [SplitDom $dom $edge $IJMinMax] == 1 } {
      set madeSplit 1
      continue
    }
    }
# ************   Edge 2
    set IJMinMax "IMaximum"
    set edge [$dom getEdge $IJMinMax]
    if { [$edge getXYZ 2] == [$edge getXYZ [$edge getDimension]] } {
    set numcon [$edge getConnectorCount]
    set cntt [expr +1]
    puts "Skipping Pole Edge: $edge with connectors"
    set conn [$edge getConnector $cntt]
    while { $cntt <= $numcon } {
    puts "$cntt [[$edge getConnector $cntt] getName]"
      set cntt [expr { $cntt + 1 }]
    }
    } else {
    if { [SplitDom $dom $edge $IJMinMax] == 1 } {
      set madeSplit 1
      continue
    }
    }
# ************   Edge 3
    set IJMinMax "JMinimum"
    set edge [$dom getEdge $IJMinMax]
    if { [$edge getXYZ 2] == [$edge getXYZ [$edge getDimension]] } {
    set numcon [$edge getConnectorCount]
    set cntt [expr +1]
    puts "Skipping Pole Edge: $edge with connectors"
    set conn [$edge getConnector $cntt]
    while { $cntt <= $numcon } {
    puts "$cntt [[$edge getConnector $cntt] getName]"
      set cntt [expr { $cntt + 1 }]
    }
    } else {
    if { [SplitDom $dom $edge $IJMinMax] == 1 } {
      set madeSplit 1
      continue
    }
    }
# ************   Edge 4
    set IJMinMax "JMaximum"
    set edge [$dom getEdge $IJMinMax]
    if { [$edge getXYZ 2] == [$edge getXYZ [$edge getDimension]] } {
    set numcon [$edge getConnectorCount]
    set cntt [expr +1]
    puts "Skipping Pole Edge: $edge with connectors"
    set conn [$edge getConnector $cntt]
    while { $cntt <= $numcon } {
    puts "$cntt [[$edge getConnector $cntt] getName]"
      set cntt [expr { $cntt + 1 }]
    }
    } else {
    if { [SplitDom $dom $edge $IJMinMax] == 1 } {
      set madeSplit 1
      continue
    }
    }
  }

# Perform Final Step
# Get any overlapping domains that were not merged
if {$madeSplit == 0} {
getoverlapdoms2
}

}

# Write out any remaing overlapping domains
 if {$domnames != ""} {
 puts "The following overlaping domains were not merged."
 puts "Overlapping Domains: $domnames"
 }

# **** End of main section
