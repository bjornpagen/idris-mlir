# Passes, as plain translation units: not yet a module.
target_sources(idr_dialect PRIVATE
	Contify.cc
	Defunctionalize.cc
	LoopBreakers.cc
	Narrow.cc
	Prune.cc
	Simplify.cc
	TailLoops.cc
)
