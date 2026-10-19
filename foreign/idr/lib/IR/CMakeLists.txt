# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The dialect: its types, attributes and ops with their hooks (verifiers,
# folders, canonicalizations, effects, asm names), the flow models of every
# op, the rules of a function and of the program, the grades, the layouts
# of cells and the type graph.
# The folders and the tag limit call the runtime natively; the runtime's
# headers reach every library that includes the dialect's.
add_mlir_dialect_library(IdrIR
	Dialect.cpp
	Bytecode.cpp
	Ops.cpp
	OpsCon.cpp
	OpsConReads.cpp
	OpsMatch.cpp
	OpsMatchSyntax.cpp
	OpsClosures.cpp
	OpsScalars.cpp
	OpsStrings.cpp
	OpsBigs.cpp
	OpsArrays.cpp
	OpsGenerating.cpp
	OpsTabulate.cpp
	OpsFolds.cpp
	OpsChecks.cpp
	OpsOwnership.cpp
	OpsPlatform.cpp
	Types.cpp
	DataBody.cpp
	ValueFacts.cpp
	Attrs.cpp
	ConAttr.cpp
	Grades.cpp
	Tail.cpp
	Lifetimes.cpp
	Effects.cpp
	Flow.cpp
	FlowEdges.cpp
	FlowOps.cpp
	Crashes.cpp
	Ranges.cpp
	Asm.cpp
	Symbols.cpp
	DataRemap.cpp
	ContentNames.cpp
	Regions.cpp
	Constants.cpp
	TypeGraph.cpp
	Func/Func.cpp
	Func/Call.cpp
	Func/Inliner.cpp
	Verify/Attributes.cpp
	Verify/Program.cpp
	Verify/Knots.cpp
	Verify/Linearity.cpp
	Verify/Owned.cpp
	Verify/OwnedOps.cpp
	Verify/OwnedRegions.cpp
	Verify/Uses.cpp
	Canon/MatchPatterns.cpp
	Canon/CaseOfCase.cpp
	Canon/Feeds.cpp
	Canon/Merge.cpp
	Canon/Sink.cpp
	Canon/Rebuild.cpp
	Canon/Eta.cpp
	Canon/MoveOut.cpp
	Canon/Output.cpp
	Canon/PutList.cpp
	Canon/Captures.cpp
	Canon/Callees.cpp
	Canon/Force.cpp
	Fold/Scope.cpp
	Fold/Values.cpp
	Fold/Bigs.cpp
	Fold/Strings.cpp
	Layout/CellInfo.cpp
	Layout/Components.cpp
	Layout/Fit.cpp
	Layout/Layouts.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen

	LINK_LIBS PUBLIC
	IdrSupport
	idris_rt
	MLIRIR
	MLIRSupport
	MLIRPass
	MLIRTransformUtils
	MLIRArithDialect
	MLIRControlFlowDialect
	MLIRUBDialect
	MLIRLLVMDialect
	MLIRSCFDialect
	MLIRTensorDialect
	MLIRMemRefDialect
	MLIRLinalgDialect
	MLIRFuncDialect
	MLIRDialectUtils
	MLIRMemRefTransforms
	MLIRFunctionInterfaces
	MLIRCallInterfaces
	MLIRControlFlowInterfaces
	MLIRInferIntRangeInterface
	MLIRInferIntRangeCommon
	MLIRInferTypeOpInterface
	MLIRValueBoundsOpInterface
	MLIRSideEffectInterfaces
	MLIRDataLayoutInterfaces
	MLIRBytecodeOpInterface
)
target_include_directories(IdrIR PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
# idr.os folds to the target's operating system.
target_compile_definitions(IdrIR PRIVATE ${IDR_TARGET_DEFINITIONS})
