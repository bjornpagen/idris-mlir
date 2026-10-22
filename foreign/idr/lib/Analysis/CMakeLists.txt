# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The solver layer: the graphs every solve runs on and their components,
# the program's graph of calls, the graph of the types that hold one
# another, which the knots' pass and exclusivity read, and the label
# solve's points and sets. It lists only its own units, under Solver/, and
# the analyses' library below checks the whole directory
# (PARTIAL_SOURCES_INTENDED).
add_mlir_library(IdrSolver
	Solver/Components.cpp
	Solver/Graph.cpp
	Solver/LabelPoints.cpp
	Solver/LabelSets.cpp
	Solver/ProgramGraph.cpp
	Solver/TypeGraph.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrSupport
	MLIRIR
	MLIRSupport
	MLIRPass
	MLIRAnalysis
)

# The analyses the pass manager caches and invalidates: what the passes
# ask of the whole module, each immutable once built.
add_mlir_library(IdrAnalysis
	BindingTimes.cpp
	Constants.cpp
	Identities.cpp
	IdentitiesRebuilds.cpp
	IdentitiesRecord.cpp
	LabelSites.cpp
	Labels.cpp
	Ownership/Borrows.cpp
	Ownership/Exclusivity.cpp
	Ownership/ExclusivityAnalyses.cpp
	Ownership/ExclusivityGraph.cpp
	Ranges.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRSupport
	MLIRPass
	MLIRAnalysis
	MLIRCallInterfaces
	MLIRControlFlowInterfaces
	MLIRInferIntRangeInterface
	MLIRLoopLikeInterface
	MLIRSideEffectInterfaces
	MLIRArithDialect
	MLIRSCFDialect
	MLIRUBDialect
)
