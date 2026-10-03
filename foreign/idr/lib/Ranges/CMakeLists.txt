# idr.ranges: the integer ranges of bigs and naturals.
idr_library(idr_ranges
	MODULES
		Ranges.cppm
		Add.cppm
		Bounds.cppm
		BoundsOf.cppm
		Mul.cppm
		OfInteger.cppm
		RangeOf.cppm
		Sub.cppm
	LINKS
		idr_mlir
)
