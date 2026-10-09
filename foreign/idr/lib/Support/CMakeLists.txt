# idr.support: actions, the counts of a pattern driver and the statistics of
# a pass's own pipeline.
idr_library(idr_support
	MODULES
		Support.cppm
		Counts.cppm
		EvalCallAction.cppm
		Perform.cppm
		RaiseAction.cppm
		SpecializeCloneAction.cppm
		Statistics.cppm
		TaggedAction.cppm
	LINKS
		idr_mlir
)
