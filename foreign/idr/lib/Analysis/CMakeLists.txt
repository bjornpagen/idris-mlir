# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The analyses the pass manager caches and invalidates: what the passes
# ask of the whole module, each immutable once built.
add_mlir_library(IdrAnalysis
	Effects.cpp
	Inline.cpp
	Constants.cpp
	BindingTimes.cpp
	Labels.cpp
	LabelSites.cpp
	Ownership/Values.cpp
	Ownership/Uses.cpp
	Ownership/Borrows.cpp
	Ownership/Reuses.cpp
	Ownership/Exclusivity.cpp
	Ownership/ExclusivityAnalyses.cpp
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
