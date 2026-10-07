# idr.tail: self tail calls made loops, tails modulo a constructor made
# destination-passing, tails modulo an addition made accumulators, and
# results that are arguments dropped; the pass glue of idr-tail-loops,
# idr-trmc, idr-accumulate and idr-returned-arguments are plain units
# that import it.
idr_library(idr_tail
	MODULES
		Tail.cppm
		Accumulator.cppm
		Decision.cppm
		Loop.cppm
		Loops.cppm
		Reaches.cppm
		Returned.cppm
		Trmc.cppm
		WhileDo.cppm
	GLUE
		Accumulator/Pass.cc
		Loops/Pass.cc
		Returned/Pass.cc
		Trmc/Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_graph
)
