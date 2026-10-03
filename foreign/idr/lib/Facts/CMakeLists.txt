# idr.facts: one partition per fact, each holding its definitions; the pass
# glue (the TableGen-declared base of idr-effects) and the hook that answers
# MemoryEffectOpInterface for func.call are plain units that import it.
idr_library(idr_facts
	MODULES
		Facts.cppm
		BreaksLast.cppm
		ClosureLabel.cppm
		Effects.cppm
		Evaluation.cppm
		Infer.cppm
		Inherit.cppm
		Inlined.cppm
		MayHoldClosure.cppm
		MayHoldWorld.cppm
		Of.cppm
		Passed.cppm
		Record.cppm
		TakesWorld.cppm
	GLUE
		CallEffects.cc
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
)
