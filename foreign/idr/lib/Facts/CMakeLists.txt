# idr.facts: its interface units declare, its implementation units define;
# the pass glue (the TableGen-declared base of idr-effects) and the hook that
# answers MemoryEffectOpInterface for func.call are plain units that import
# it.
idr_library(idr_facts
	MODULES
		Facts.cppm
		Closures.cppm
		Effects.cppm
		Evaluation.cppm
		Functions.cppm
		Infer.cppm
	UNITS
		Closures/ClosureLabel.cc
		Closures/MayHoldClosure.cc
		Closures/Passed.cc
		Effects/Effects.cc
		Evaluation/CanEvaluate.cc
		Functions/BreaksLast.cc
		Functions/Inherit.cc
		Functions/Inlined.cc
		Functions/MayHoldWorld.cc
		Functions/Of.cc
		Functions/Record.cc
		Functions/TakesWorld.cc
		Infer/Infer.cc
	GLUE
		CallEffects.cc
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
)
