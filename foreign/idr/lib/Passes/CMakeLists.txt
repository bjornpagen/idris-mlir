# Passes, as plain translation units: not yet a module.
target_sources(idr_dialect PRIVATE
	Defunctionalize.cc
	LoopBreakers.cc
	Prune.cc
	Simplify.cc
	TailLoops.cc
)
