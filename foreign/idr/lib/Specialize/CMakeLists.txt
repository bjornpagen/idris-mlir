# idr.specialize: raising and specialization, and the binding times they
# decide by. The glue of idr-specialize and idr-binding-times is a plain
# unit that imports it.
idr_library(idr_specialize
	MODULES
		Specialize.cppm
		BindingTime.cppm
		BindingTimes.cppm
		Clones.cppm
		EraseUnused.cppm
		HasStructure.cppm
		Interpreter.cppm
		IsClosed.cppm
		KeyOf.cppm
		Labels.cppm
		OperandsFor.cppm
		ParameterAttrs.cppm
		Pattern.cppm
		Raise.cppm
		Rebuild.cppm
		Renumber.cppm
		ShapeOf.cppm
		Specialization.cppm
		Specializer.cppm
		UnrollSize.cppm
		UsedOnce.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_support
		idr_graph
		idr_facts
)
