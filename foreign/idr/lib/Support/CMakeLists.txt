# idr.support: actions, the counts of a pattern driver and the statistics of
# a pass's own pipeline. EnableStatistics.h is no part of it: every unit is
# compiled with it first (PIN(llvm-force-enable-stats)).
idr_library(idr_support
	MODULES
		Support.cppm
		Actions.cppm
		Counts.cppm
		Statistics.cppm
	UNITS
		Actions/EvalCallAction.cc
		Actions/RaiseAction.cc
		Actions/SpecializeCloneAction.cc
		Counts/PatternCounts.cc
		Statistics/PipelineStatistics.cc
	LINKS
		idr_mlir
)
