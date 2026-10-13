# The analyses the pass manager caches and invalidates: what the passes
# ask of the whole module, each immutable once built.
add_mlir_library(IdrAnalysis
	References.cpp
	Effects.cpp
	Holds.cpp
	Inline.cpp
	Specialize.cpp
	BindingTimes.cpp
	Labels.cpp
	LabelSites.cpp
	Ownership/Values.cpp
	Ownership/Uses.cpp
	Ownership/Borrows.cpp
	Ownership/Reuses.cpp
	Ownership/Exclusivity.cpp
	Tail.cpp
	Ranges.cpp
	Escapes.cpp
	EscapesCycles.cpp
	Identities.cpp
	IdentitiesRecord.cpp
	IdentitiesRebuilds.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrSupport
	MLIRIR
	MLIRSupport
	MLIRPass
	MLIRAnalysis
	MLIRCallInterfaces
	MLIRInferIntRangeInterface
	MLIRSideEffectInterfaces
	MLIRArithDialect
	MLIRSCFDialect
	MLIRUBDialect
)
