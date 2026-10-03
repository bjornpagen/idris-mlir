# Passes, as plain translation units: not yet a module.
target_sources(idr_dialect PRIVATE
	Contify.cc
	Defunctionalize.cc
	LoopBreakers.cc
	Narrow.cc
	Prune.cc
	ReturnedArguments.cc
	Simplify.cc
	Tail.cc
	TailLoops.cc
	Target.cc
	Trmc.cc
	Vectorize.cc
)
