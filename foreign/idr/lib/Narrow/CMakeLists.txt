# idr.narrow: bigs made words where integer range analysis proves they fit,
# and the integer lanes of vectorized loops made 32 bits under a runtime
# bound; the pass glue of idr-narrow and idr-narrow-lanes are plain units
# that import it.
idr_library(idr_narrow
	MODULES
		Narrow.cppm
		Carried.cppm
		Copy.cppm
		Facts.cppm
		Lanes.cppm
		Naturals.cppm
		Ops.cppm
		Versions.cppm
		Widths.cppm
		Words.cppm
	GLUE
		Pass.cc
		Lanes/Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_graph
		idr_ownership
		idr_ranges
)
