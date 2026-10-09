# idr.defunctionalize: closures and suspensions of known labels made sums, by
# a dataflow analysis of the labels each closure or suspension may hold, and
# then the boxes that make cells fit (idr.layout); the pass glue of
# idr-defunctionalize is a plain unit that imports it.
idr_library(idr_defunctionalize
	MODULES
		Defunctionalize.cppm
		Analysis.cppm
		ByName.cppm
		Closures.cppm
		Converter.cppm
		Decided.cppm
		Declared.cppm
		Labels.cppm
		Moves.cppm
		Slots.cppm
		Sums.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_graph
		idr_layout
)
