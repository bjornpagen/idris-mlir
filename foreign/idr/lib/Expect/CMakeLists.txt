# idr.expect: the properties idr-expect checks, one partition each; the pass
# glue (the TableGen-declared base of idr-expect) is a plain unit that
# imports it. folds-balanced reads the count of cells the folders left
# live, which the idr dialect keeps per context; resets-unshared reads what
# idr.ownership says a value was read from; the guard properties read
# idr.inbounds's list of guards.
idr_library(idr_expect
	MODULES
		Expect.cppm
		Allocation.cppm
		BreaksLast.cppm
		Clones.cppm
		Closures.cppm
		ConstantStack.cppm
		Continuations.cppm
		CountedLoop.cppm
		CountsNothing.cppm
		EveryCycleHasBreaker.cppm
		Facts.cppm
		Folds.cppm
		InBounds.cppm
		Lookup.cppm
		Named.cppm
		NarrowedLanes.cppm
		Output.cppm
		PureArrayLoops.cppm
		Quantities.cppm
		References.cppm
		Report.cppm
		ResetsUnshared.cppm
		ReusesEveryCell.cppm
		ReusesInPlace.cppm
		Roots.cppm
		TestsNothing.cppm
		Vectorized.cppm
		Words.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_facts
		idr_graph
		idr_inbounds
		idr_ownership
)
