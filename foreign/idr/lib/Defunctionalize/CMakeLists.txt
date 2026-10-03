# idr.defunctionalize: closures of known labels made sums, by a dataflow
# analysis of the labels each closure may hold; the pass glue of
# idr-defunctionalize is a plain unit that imports it.
idr_library(idr_defunctionalize
	MODULES
		Defunctionalize.cppm
		Analysis.cppm
		Closures.cppm
		Converter.cppm
		Decided.cppm
		Labels.cppm
		Slots.cppm
		Sums.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_graph
)
