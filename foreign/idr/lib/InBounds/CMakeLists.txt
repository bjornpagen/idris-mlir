# idr.inbounds: the guards proven never to crash, which it erases; the pass
# glue of idr-in-bounds is a plain unit that imports it.
idr_library(idr_inbounds
	MODULES
		Components.cppm
		Guards.cppm
		InBounds.cppm
		Induction.cppm
		Joins.cppm
		Lengths.cppm
		Linear.cppm
		Masks.cppm
		Paths.cppm
		Prove.cppm
		Quotients.cppm
		Returned.cppm
		System.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_graph
		idr_narrow
)
