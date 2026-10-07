# idr.simplify: the simplify loop's round and the passes only it runs (loop
# breakers) or that prepare for it (contify); the pass glue of
# idr-simplify, idr-loop-breakers, idr-contify and idr-dead-values are
# plain units that import it.
idr_library(idr_simplify
	MODULES
		Simplify.cppm
		Breakers.cppm
		Contify.cppm
		DeadValues.cppm
		Round.cppm
		Trace.cppm
	GLUE
		Pass.cc
		Breakers/Pass.cc
		Contify/Pass.cc
		DeadValues/Pass.cc
	LINKS
		idr_mlir
		idr_facts
		idr_graph
		idr_support
)
