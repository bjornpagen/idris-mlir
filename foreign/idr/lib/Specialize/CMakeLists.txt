# Specialize, as plain translation units: not yet a module.
target_sources(idr_dialect PRIVATE
	BindingTimes.cc
	Clones.cc
	Pass.cc
	Pattern.cc
	Raise.cc
	Run.cc
	Specialize.cc
)
