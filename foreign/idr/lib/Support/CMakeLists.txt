# idr.support: actions, the counts of a pattern driver and the statistics of
# a pass's own pipeline. EnableStatistics.h is no part of it: every unit is
# compiled with it first (PIN(llvm-force-enable-stats)).
idr_library(idr_support
	MODULES
		Support.cppm
		Counts.cppm
		EvalCallAction.cppm
		Perform.cppm
		RaiseAction.cppm
		SpecializeCloneAction.cppm
		Statistics.cppm
	LINKS
		idr_mlir
)
