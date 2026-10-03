# idr.stack: which boxes are built in their function's frame; the pass glue
# (the TableGen-declared base of idr-stack) is a plain unit that imports it.
idr_library(idr_stack
	MODULES
		Stack.cppm
		Escape.cppm
		Mark.cppm
		Recursion.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_graph
		idr_layout
)
