# idr.graph: strongly connected components, tail position and loop trips,
# which the passes of several areas share.
idr_library(idr_graph
	MODULES
		Graph.cppm
		FieldsOf.cppm
		InTailPosition.cppm
		InTailPositionModuloConstructor.cppm
		IsSelfCall.cppm
		ModuloAt.cppm
		PassesOnPrevious.cppm
		References.cppm
		RefersTo.cppm
		Scc.cppm
		SymbolUses.cppm
		Trips.cppm
	LINKS
		idr_mlir
		idr_ods
)
