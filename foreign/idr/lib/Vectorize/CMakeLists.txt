# idr.vectorize: the loops over arrays tiled and vectorized at the target's
# lanes; the pass glue of idr-vectorize is a plain unit that imports it.
idr_library(idr_vectorize
	MODULES
		Vectorize.cppm
		Tiles.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_target
)
