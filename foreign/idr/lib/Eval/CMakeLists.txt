# idr.eval: compile-time evaluation, which runs closed calls through ORC's
# LLJIT on the runtime linked natively (idris_rt.h and its entry points,
# whose include directory idris_rt gives) in a child process. The glue of
# idr-eval is a plain unit that imports it.
idr_library(idr_eval
	MODULES
		Eval.cppm
		Calls.cppm
		Child.cppm
		Encoding.cppm
		Evaluate.cppm
		Jit.cppm
		Phases.cppm
		Reify.cppm
		Round.cppm
		Scratch.cppm
	UNITS
		Boxes.cc
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_support
		idr_defunctionalize
		idr_facts
		idr_layout
		idr_target
		idris_rt
)
