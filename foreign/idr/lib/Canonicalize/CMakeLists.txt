# idr.canonicalize: canonicalize with its rewrites counted; the pass glue
# (the TableGen-declared base of idr-canonicalize) is a plain unit that
# imports it.
idr_library(idr_canonicalize
	MODULES
		Canonicalize.cppm
		Counted.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_support
)
