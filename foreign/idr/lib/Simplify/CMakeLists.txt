# idr.simplify: the simplify loop's round and the passes only it runs (loop
# breakers, pruning) or that prepare for it (contify); the pass glue of
# idr-simplify, idr-loop-breakers, idr-prune and idr-contify are plain units
# that import it.
idr_library(idr_simplify
	MODULES
		Simplify.cppm
		Breakers.cppm
		Contify.cppm
		Prune.cppm
		Round.cppm
		Structural.cppm
		Trace.cppm
	GLUE
		Pass.cc
		Breakers/Pass.cc
		Contify/Pass.cc
		Prune/Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_facts
		idr_graph
		idr_support
)
