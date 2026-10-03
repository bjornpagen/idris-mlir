# idr.graph: strongly connected components, tail position and loop trips,
# which the passes of several areas share.
idr_library(idr_graph
	MODULES
		Graph.cppm
		Scc.cppm
		Tail.cppm
		Trips.cppm
	UNITS
		Scc/Components.cc
		Tail/FieldsOf.cc
		Tail/InTailPosition.cc
		Tail/InTailPositionModuloConstructor.cc
		Tail/IsSelfCall.cc
		Tail/ModuloAt.cc
		Tail/PassesOnPrevious.cc
		Trips/RunsAtMostOnce.cc
	LINKS
		idr_mlir
		idr_ods
)
