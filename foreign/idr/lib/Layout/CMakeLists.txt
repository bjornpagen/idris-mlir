# idr.layout: how values are represented at runtime. It reads the runtime's
# C ABI (idris_rt.h), whose include directory idris_rt gives.
idr_library(idr_layout
	MODULES
		Layout.cppm
		CellInfo.cppm
		Cells.cppm
		CodeName.cppm
		Labels.cppm
		Layouts.cppm
		Sums.cppm
	LINKS
		idr_mlir
		idr_ods
		idris_rt
)
