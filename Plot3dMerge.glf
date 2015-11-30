#
# Copyright 2015 (c) Pointwise, Inc.
# All rights reserved.
#
# This sample script is not supported by Pointwise, Inc.
# It is provided freely for demonstration purposes only.
# SEE THE WARRANTY DISCLAIMER AT THE BOTTOM OF THIS FILE.
#

package require PWI_Glyph 2

set tol       [pw::Database getSamePointTolerance]
set verbose   1  ;# set 1 to generate trace/debug output


proc vputs { msg } {
  global verbose
  if { $verbose } {
    puts $msg
  }
}

proc getUniqueConNodes { cons } {
  set ret [list]
  foreach con $cons {
    lappend ret [$con getNode 1] [$con getNode 2]
  }
  return [lsort -unique -dictionary $ret]
}


proc getCoordAtXYZ { ent xyz coordVar } {
  upvar $coordVar coord
  global tol
  set ret 0
  set coord [$ent closestCoordinate -distance dist $xyz]
  if { $dist < $tol } {
    set ret 1
  }
  return $ret
}


proc getInteriorCoordAtXYZ { ent xyz coordVar } {
  upvar $coordVar coord
  global tol
  set ret 0
  if { [getCoordAtXYZ $ent $xyz coord] } {
    set ndx [lrange $coord 0 end-1]
    set ret [$ent isInteriorIndex $ndx]
  }
  return $ret
}


proc getDomEdges { dom } {
  return [list [$dom getEdge 1] [$dom getEdge 2] [$dom getEdge 3] \
    [$dom getEdge 4]]
}


proc getUniqueDomCons { doms } {
  set ret [list]
  foreach dom $doms {
    set numEdges [$dom getEdgeCount]
    for {set ii 1} {$ii <= $numEdges} {incr ii} {
      set edge [$dom getEdge $ii]
      set numCons [$edge getConnectorCount]
      for {set jj 1} {$jj <= $numCons} {incr jj} {
        lappend ret [$edge getConnector $jj]
      }
    }
  }
  return [lsort -unique -dictionary $ret]
}


proc buildEntInteriorNodeMap { entType entsToSplitVar } {
  vputs "Building $entType interior node map..."
  upvar $entsToSplitVar entsToSplit
  # Build a ent:nodes map. Where each ent needs to be split at one or more
  # interior grid point locations that are coincident with each node.
  set ents [pw::Grid getAll -type pw::$entType]
  if { {Connector} == "$entType" } {
    set nodes [getUniqueConNodes $ents]
  } else {
    set nodes [getUniqueConNodes [pw::Grid getAll -type pw::Connector]]
  }
  set entsToSplit [dict create]
  foreach node $nodes {
    set xyz [$node getXYZ]
    foreach ent $ents {
      if { [getInteriorCoordAtXYZ $ent $xyz coord] } {
        # ent has an interior coord at xyz that is coincident with node
        dict lappend entsToSplit $ent $node
      }
    }
  }
  return [expr {0 != [dict size $entsToSplit]}]
}


proc buildDomInteriorNodeMap { domsToSplitVar } {
  upvar $domsToSplitVar domsToSplit
  return [buildEntInteriorNodeMap DomainStructured domsToSplit]
}


proc buildConInteriorNodeMap { consToSplitVar } {
  upvar $consToSplitVar consToSplit
  return [buildEntInteriorNodeMap Connector consToSplit]
}


proc splitDomAtIJ { dom IorJ ndx } {
  if { [catch {$dom split -$IorJ $ndx} ret] } {
    set ret $dom
  } else {
    vputs "> $IorJ $ndx of dim[list [$dom getDimensions]] [$dom getName]"
  }
  return $ret
}


proc splitDomAtOneNode { dom node } {
  set ret [list] ;# return all doms created by splitting dom
  set xyz [$node getXYZ]
  if { [getCoordAtXYZ $dom $xyz coord] } {
    # coord = {i j dom}
    lassign $coord i j
    # Split dom at I location. Then, split resulting doms at the J location.
    foreach dom [splitDomAtIJ $dom I $i] {
      lappend ret {*}[splitDomAtIJ $dom J $j]
    }
  } else {
    # dom not split, return as-is
    set ret $dom
  }
  return $ret
}


proc splitDomAtNodes { dom nodes } {
  puts "Splitting domain '[$dom getName]' at [llength $nodes] interior nodes..."
  set newDoms [list $dom]
  foreach node $nodes {
    set domsToProcess $newDoms
    set newDoms [list]
    foreach dom $domsToProcess {
      lappend newDoms {*}[splitDomAtOneNode $dom $node]
    }
  }
  # return all doms created by splitting dom
  return $newDoms
}


proc splitDomsAtInteriorNodes { } {
  if { [buildDomInteriorNodeMap domsToSplit] } {
    set pass 0
    dict for {dom nodes} $domsToSplit {
      puts "[incr pass] of [dict size $domsToSplit]..."
      set domName [$dom getName]
      # this does an agressive split of dom
      set allSplitDoms [splitDomAtNodes $dom $nodes]

      # Entity auto-merge has happened by now. Join allSplitDoms back together to
      # eliminate unneeded splits. Then join the dom cons to eliminate unneeded
      # nodes.
      vputs "cleaning up domains..."
      set doms [pw::DomainStructured join -reject rejects $allSplitDoms]
      lappend doms {*}$rejects
      # shorten split dom names
      set cln [pw::Collection create]
      $cln set $doms
      $cln do setName "domm_xxxxxx-1"
      $cln do setName "$domName-split-1"
      $cln delete
      unset cln
      vputs "$domName was split into [llength $doms] domains"

      vputs "cleaning up connectors..."
      set cons [getUniqueDomCons $doms]
      pw::Connector join -keepDistribution $cons

      splitDomsAtBoundaryNodes $nodes
      splitOverlappingDoms
    }
  } else {
    vputs "No interior nodes found."
  }
}


proc splitConsAtInteriorNodes { } {
  while { [buildConInteriorNodeMap consToSplit] } {
    set bndryNodes [list]
    dict for {con nodes} $consToSplit {
      splitConAtNodes $con $nodes
      lappend bndryNodes {*}$nodes
    }
    splitDomsAtBoundaryNodes $bndryNodes
    splitOverlappingDoms
  }
  vputs "No interior connector nodes found."
}


proc splitConAtNodes { con nodes } {
  vputs "Splitting connector '[$con getName]' at [llength $nodes] interior nodes..."
  set iparams [list]
  foreach node $nodes {
    set xyz [$node getXYZ]
    if { [getCoordAtXYZ $con $xyz coord] } {
      # coord = {i con}
      lappend iparams [lindex $coord 0]
    }
  }
  # return all cons created by splitting con
  return [$con split -I $iparams]
}


proc splitDomsAtBoundaryNodes { bndryNodes } {
  puts "Splitting domains at [llength $bndryNodes] boundary nodes..."
  foreach node $bndryNodes {
    if { ![getUniqueConsAndDomsAtNode $node cons doms] } {
      continue
    }
    foreach con $cons {
      splitDomsAtConNode $doms $con $node
    }
  }
}


proc splitOverlappingDoms { } {
  vputs "Processing overlapping domains..."
  foreach dom [pw::Grid getAll -type pw::DomainStructured] {
    set olapDoms [pw::DomainStructured getOverlappingDomains [getDomEdges $dom]]
    if { -1 != [set pos [lsearch $olapDoms $dom]] } {
      set olapDoms [lreplace $olapDoms $pos $pos]
    }
    if { 0 == [llength $olapDoms] } {
      continue
    }
    if { [getUniqueConsAndNodesFromDoms $olapDoms cons nodes] } {
      splitDomsAtBoundaryNodes $nodes
    }
  }
}


proc getUniqueConsAndNodesFromDoms { doms consVar nodesVar } {
  upvar $consVar cons
  upvar $nodesVar nodes
  set ret 0
  set cons [getUniqueDomCons $doms]
  if { 0 != [llength $cons] } {
    set nodes [getUniqueConNodes $cons]
    if { 0 != [llength $nodes] } {
      set ret 1
    }
  }
  return $ret
}


proc getUniqueConsAndDomsAtNode { node consVar domsVar } {
  upvar $consVar cons
  upvar $domsVar doms
  set ret 0
  set cons [$node getConnectors]
  if { 0 != [llength $cons] } {
    set cons [lsort -unique -dictionary $cons]
    set doms [pw::Domain getDomainsFromConnectors $cons]
    if { 0 != [llength $doms] } {
      set doms [lsort -unique -dictionary $doms]
      set ret 1
    }
  }
  return $ret
}


proc splitDomsAtConNode { doms con node } {
  # get xyz of con grid point next to node
  if { $node == [$con getNode 1] } {
    set xyz [$con getXYZ 2]
  } elseif { $node == [$con getNode 2] } {
    set xyz [$con getXYZ [$con getCellCount]]
  }
  # get domains that already contain con
  #set conDoms [lsort [pw::Domain getDomainsFromConnectors [list $con]]]
  foreach dom $doms {
    # This stops self-connected blocks from working. But commenting it out slows
    # things down. Probably should be a setting.
    #if { -1 != [lsearch -exact -sorted $conDoms $dom] } {
    #  # dom already contains con. skip it.
    #  puts "skip conDoms: [$con getName] in $conDoms"
    #  continue
    #}

    # dom uses node from one end of con. check if con points are coincident with
    # dom points
    if { [getInteriorCoordAtXYZ $dom $xyz coord] } {
      # dom has an interior coord at xyz that is coincident with con. Split dom
      # at node
      splitDomAtOneNode $dom $node
    }
  }
}


proc doMerge {} {
  puts "Merging..."
  puts "*** Procesing domains..."
  splitDomsAtInteriorNodes
  puts "*** Procesing connectors..."
  splitConsAtInteriorNodes
}

#----------------------------------------------------------------------------
#----------------------------------------------------------------------------
#----------------------------------------------------------------------------

doMerge

# END SCRIPT

#
# DISCLAIMER:
# TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, POINTWISE DISCLAIMS
# ALL WARRANTIES, EITHER EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED
# TO, IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE, WITH REGARD TO THIS SCRIPT.  TO THE MAXIMUM EXTENT PERMITTED 
# BY APPLICABLE LAW, IN NO EVENT SHALL POINTWISE BE LIABLE TO ANY PARTY 
# FOR ANY SPECIAL, INCIDENTAL, INDIRECT, OR CONSEQUENTIAL DAMAGES 
# WHATSOEVER (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF 
# BUSINESS INFORMATION, OR ANY OTHER PECUNIARY LOSS) ARISING OUT OF THE 
# USE OF OR INABILITY TO USE THIS SCRIPT EVEN IF POINTWISE HAS BEEN 
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGES AND REGARDLESS OF THE 
# FAULT OR NEGLIGENCE OF POINTWISE.
#
