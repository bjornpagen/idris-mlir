# idr.demand: the promises a program can be asked to keep, checked on the
# grades idr-rc wrote; the pass glue (the TableGen-declared base of
# idr-demand) is a plain unit that imports it.
idr_library(idr_demand
	MODULES
		Demand.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
)
