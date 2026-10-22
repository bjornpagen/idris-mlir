# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The dialect: its types, attributes and ops with their hooks (verifiers,
# folders, effects, asm names, skeleton rules), the families, the counting,
# lifetime, control and tail ops, the flow models of every op, the rules of
# a function and of the program, the grades and the layouts of cells.
# The folders and the tag limit call the runtime natively; the runtime's
# headers reach every library that includes the dialect's. The skeleton
# rules read what the e-graph knows of their operands through its headers
# alone; the e-graph, which calls them, links the dialect.
#
# The one precompiled header of the build, which every library that links
# the dialect reuses (and each executable of ours that does, by
# REUSE_FROM): the C++ library and LLVM's ADT and support headers as LLVM
# precompiles them, MLIR's core headers as MLIR precompiles them, and the
# dialect's own header with the declarations generated from its ODS. The
# vocabulary under idr/Support stays out, so an edit of it rebuilds no
# precompiled header, and a unit that misses one of its includes still
# fails to compile.
find_file(IDR_LLVM_PCH llvm/Support/pch.h PATHS ${LLVM_INCLUDE_DIRS} NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH REQUIRED)
find_file(IDR_MLIR_PCH mlir/IR/pch.h PATHS ${MLIR_INCLUDE_DIRS} NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH REQUIRED)
add_mlir_dialect_library(IdrIR
	Asm.cpp
	Attrs.cpp
	Bytecode.cpp
	ConAttr.cpp
	Constants.cpp
	ContentNames.cpp
	Control/Joins.cpp
	Control/JoinsSyntax.cpp
	Control/Jump.cpp
	Control/LiteralMatch.cpp
	Counting/CellInit.cpp
	Counting/Flow.cpp
	Counting/Ops.cpp
	Counting/Takes.cpp
	Counting/Types.cpp
	Dialect.cpp
	Effects.cpp
	Effects/Conditions.cpp
	Families/Bytecode.cpp
	Families/DataNormal.cpp
	Families/DataSyntax.cpp
	Families/Directives.cpp
	Families/Family.cpp
	Families/FamilyQueries.cpp
	Families/FamilySyntax.cpp
	Families/FamilyVerify.cpp
	Families/Matching.cpp
	Families/Members.cpp
	Families/Refinement.cpp
	Families/Rules.cpp
	Families/ScopeWalk.cpp
	Families/Scopes.cpp
	Families/SubElements.cpp
	Families/Substitute.cpp
	Families/TermSyntax.cpp
	Families/Terms.cpp
	Families/Unify.cpp
	Flow.cpp
	FlowEdges.cpp
	FlowOps.cpp
	Fold/Scope.cpp
	Fold/Values.cpp
	Func/Call.cpp
	Func/Edits.cpp
	Func/Extents.cpp
	Func/Fold.cpp
	Func/Func.cpp
	Func/GivenBack.cpp
	Func/Inliner.cpp
	Func/LivesIn.cpp
	Func/Program.cpp
	Func/Rows.cpp
	Func/Values.cpp
	Func/Verifier.cpp
	Grades.cpp
	Layout/CellInfo.cpp
	Layout/Classes.cpp
	Layout/Components.cpp
	Layout/Layouts.cpp
	Layout/Reach.cpp
	Layout/Slots.cpp
	Lifetimes/Cast.cpp
	Lifetimes/Kind.cpp
	Lifetimes/Loans.cpp
	Lifetimes/Ops.cpp
	Lifetimes/Proof.cpp
	Lifetimes/Spine.cpp
	Lifetimes/Verify.cpp
	Ops.cpp
	Ops/Constraints.cpp
	Ops/IO.cpp
	Ops/Laws.cpp
	Ops/Numeric.cpp
	Ops/Rules.cpp
	Ops/Sites.cpp
	OpsArrayFusion.cpp
	OpsArrayMovements.cpp
	OpsArrayRules.cpp
	OpsArrayShapes.cpp
	OpsArrays.cpp
	OpsBigs.cpp
	OpsChecks.cpp
	OpsClosures.cpp
	OpsCon.cpp
	OpsConReads.cpp
	OpsGenerating.cpp
	OpsMatch.cpp
	OpsMatchSyntax.cpp
	OpsPlatform.cpp
	OpsScalars.cpp
	OpsStrings.cpp
	OpsTabulate.cpp
	Ranges.cpp
	Regions.cpp
	Symbols.cpp
	Tail.cpp
	Tail/Context.cpp
	Tail/Destinations.cpp
	TypeLiterals.cpp
	Types.cpp
	ValueFacts.cpp
	Verify/Attributes.cpp
	Verify/Linearity.cpp
	Verify/Local.cpp
	Verify/Program.cpp
	Verify/Uses.cpp

	PRECOMPILE_HEADERS
	${IDR_LLVM_PCH}
	${IDR_MLIR_PCH}
	${CMAKE_CURRENT_SOURCE_DIR}/../../include/idr/IR/IdrDialect.h

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrSupport
	idris_rt
	MLIRIR
	MLIRSupport
	MLIRPass
	MLIRTransformUtils
	MLIRArithDialect
	MLIRBufferizationDialect
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
	MLIRDestinationStyleOpInterface
	MLIRInferIntRangeInterface
	MLIRInferIntRangeCommon
	MLIRInferTypeOpInterface
	MLIRLoopLikeInterface
	MLIRTilingInterface
	MLIRValueBoundsOpInterface
	MLIRViewLikeInterface
	MLIRSideEffectInterfaces
	MLIRDataLayoutInterfaces
	MLIRBytecodeOpInterface
)
target_include_directories(IdrIR PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
