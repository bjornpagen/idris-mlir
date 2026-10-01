# idr.facts: its interface units declare, its implementation units define;
# the pass glue (the TableGen-declared base of idr-effects) is a plain
# translation unit that imports it.
target_sources(idr_dialect
	PRIVATE
		FILE_SET idr_facts TYPE CXX_MODULES FILES
			Facts.cppm
			Closures.cppm
			Effects.cppm
			Evaluation.cppm
			Functions.cppm
			Infer.cppm
	PRIVATE
		CallEffects.cc
		Closures/ClosureLabel.cc
		Closures/MayHoldClosure.cc
		Closures/Passed.cc
		Effects/Effects.cc
		Evaluation/CanEvaluate.cc
		Functions/Inherit.cc
		Functions/IsLibrary.cc
		Functions/MayHoldWorld.cc
		Functions/Of.cc
		Functions/Record.cc
		Functions/TakesWorld.cc
		Infer/Infer.cc
		Pass.cc
)
