# Eval, as plain translation units: not yet a module.
target_sources(idr_dialect PRIVATE
	Child.cc
	Eval.cc
	Jit.cc
	Reify.cc
)
