# idr.isolate: the outlining of every lambda and delay into a function of
# its own; the pass glue (the TableGen-declared base of idr-isolate) is a
# plain unit that imports it.
idr_library(idr_isolate
	MODULES
		Isolate.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
)
