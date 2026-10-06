# idr.inbounds: the array accesses proven within their arrays, whose bounds
# checks lowering then leaves out; the pass glue of idr-in-bounds is a plain
# unit that imports it.
idr_library(idr_inbounds
	MODULES
		InBounds.cppm
		Joins.cppm
		Lengths.cppm
		Linear.cppm
		Paths.cppm
		Prove.cppm
		System.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_graph
		idr_narrow
)
