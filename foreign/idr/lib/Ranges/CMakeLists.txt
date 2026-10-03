# idr.ranges: the integer ranges of bigs and naturals.
idr_library(idr_ranges
	MODULES
		Ranges.cppm
		Bounds.cppm
	UNITS
		Bounds/Add.cc
		Bounds/Bounded.cc
		Bounds/Bounds.cc
		Bounds/BoundsOf.cc
		Bounds/Mul.cc
		Bounds/Natural.cc
		Bounds/OfInteger.cc
		Bounds/RangeOf.cc
		Bounds/Sub.cc
	LINKS
		idr_mlir
)
