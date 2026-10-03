# idr.inlining: what idr-inline inlines; the pass glue (the TableGen-declared
# base of idr-inline, which runs MLIR's inliner) is a plain unit that
# imports it.
idr_library(idr_inlining
	MODULES
		Inline.cppm
		Decisions.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_facts
		idr_graph
)
