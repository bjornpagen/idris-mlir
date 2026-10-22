# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The passes: one library per area, and the pipeline that orders them.
# LLVM's build checks that a directory's library lists every .cpp in it;
# here the areas share the directory with the pipeline, whose library comes
# last and checks the whole, and each area's says it lists only its own
# (PARTIAL_SOURCES_INTENDED). Every area includes the pipeline's header for
# the base its passes derive from, a template, and links no pipeline for
# it.

# idr-simplify: the e-graph over a function's ops, its rules and laws
# generated from the specification, with the interval analysis it reads
# operands by. It calls the skeleton rules the specification names, which
# the dialect, the joins and defunctionalization declare, so it links their
# libraries; they read it through its headers alone and link it not.
add_mlir_library(IdrEGraph
	EGraph/Build.cpp
	EGraph/Elaborate.cpp
	EGraph/Nodes.cpp
	EGraph/Rules.cpp
	EGraph/Simplify.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrDefunctionalize
	IdrJoins
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRArithDialect
	MLIRCallInterfaces
	MLIRControlFlowInterfaces
	MLIRInferIntRangeInterface
	MLIRInferIntRangeCommon
	MLIRSideEffectInterfaces
)

# The one construction of join points, from the jump graph, and the
# rewrites of the control-flow ops the e-graph applies as skeleton rules:
# case of case, identical regions, yielded fields.
add_mlir_library(IdrJoins
	Joins/CaseOfCase.cpp
	Joins/IdenticalRegions.cpp
	Joins/JoinRules.cpp
	Joins/Joins.cpp
	Joins/MatchRules.cpp
	Joins/Rules.cpp
	Joins/YieldedFields.cpp

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
	MLIRControlFlowInterfaces
	MLIRUBDialect
)

# The rows every function and call holds, written from their derivation,
# and idr-constants, the step idr-optimize's inner pipeline ends with,
# which reads the optimizer's schedule through its header alone.
add_mlir_library(IdrEffects
	Effects/Component.cpp
	Effects/Constants.cpp
	Effects/Parts.cpp
	Effects/Writer.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRAnalysis
	MLIRTransformUtils
	MLIRSideEffectInterfaces
	MLIRArithDialect
)

# idr-inline, upstream's inliner by MLton's rule on the callee's final
# size, and the leaf inlining the optimizer's inner pipeline runs.
add_mlir_library(IdrInline
	Inline/Inline.cpp
	Inline/InlinePass.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrEGraph
	IdrEffects
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRAnalysis
	MLIRTransforms
	MLIRTransformUtils
)

# idr-deduplicate: one function of each class of equal ones.
add_mlir_library(IdrDeduplicate
	Deduplicate/Deduplicate.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
)

# The specialization nodes, raising and idr-redirect: the calls of a node's
# key, and the copies a key names.
add_mlir_library(IdrSpecialize
	Specialize/Arena.cpp
	Specialize/Consumer.cpp
	Specialize/Keys.cpp
	Specialize/Lift.cpp
	Specialize/Order.cpp
	Specialize/Patterns.cpp
	Specialize/Raise.cpp
	Specialize/Redirect.cpp
	Specialize/Requests.cpp
	Specialize/Specialization.cpp
	Specialize/Specialize.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrDeduplicate
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRAnalysis
	MLIRRewrite
	MLIRTransformUtils
	MLIRArithDialect
)

# idr-optimize, its schedule over the call graph's components and the
# inner pipeline each function runs on it, and idr-contify. Its inner steps
# (effects, inline, specialize) read the schedule it builds through its
# header alone.
add_mlir_library(IdrOptimize
	Optimize/CaptureDrops.cpp
	Optimize/Captures.cpp
	Optimize/Component.cpp
	Optimize/Contify.cpp
	Optimize/Demand.cpp
	Optimize/Optimize.cpp
	Optimize/Results.cpp
	Optimize/Schedule.cpp
	Optimize/Settle.cpp
	Optimize/Waves.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrEGraph
	IdrEffects
	IdrInline
	IdrJoins
	IdrSolver
	IdrSpecialize
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRAnalysis
	MLIRTransforms
	MLIRTransformUtils
	MLIRArithTransforms
	MLIRUBDialect
)

# idr-defunctionalize, as one dialect conversion of the module.
add_mlir_library(IdrDefunctionalize
	Defunctionalize/Convert.cpp
	Defunctionalize/Decide.cpp
	Defunctionalize/Declare.cpp
	Defunctionalize/Edits.cpp
	Defunctionalize/Forces.cpp
	Defunctionalize/Indices.cpp
	Defunctionalize/Pass.cpp
	Defunctionalize/Rules.cpp
	Defunctionalize/Walk.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrEffects
	IdrJoins
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRTransformUtils
	MLIRUBDialect
)

# Counting's steps (idr-rc-cells, idr-rc-borrows, idr-rc-place,
# idr-rc-reuse, idr-rc-expand) and the frame bound reuse writes on each
# function, which the lowering's frame account reads.
add_mlir_library(IdrCounting
	Counting/Borrows.cpp
	Counting/Bound.cpp
	Counting/Cells.cpp
	Counting/Expand.cpp
	Counting/Placement.cpp
	Counting/PlacementRewrite.cpp
	Counting/PlacementUses.cpp
	Counting/PlacementWalk.cpp
	Counting/Reuse.cpp
	Counting/ReuseAssign.cpp
	Counting/ReuseDemand.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRArithDialect
	MLIRControlFlowInterfaces
	MLIRFunctionInterfaces
	MLIRLoopLikeInterface
	MLIRSCFDialect
)

# idr-lifetimes: the decide step, read, decided callee first and written
# at once, so every lifetime is born decided.
add_mlir_library(IdrLifetimes
	Lifetimes/Decide.cpp
	Lifetimes/Pass.cpp
	Lifetimes/Read.cpp
	Lifetimes/Write.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrEffects
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRControlFlowInterfaces
)

# idr-unique-results and idr-in-place: the local rule's unique results
# before bufferization, and the in-place promise held at its sites.
add_mlir_library(IdrInPlace
	InPlace/Chains.cpp
	InPlace/InPlace.cpp
	InPlace/Rule.cpp
	InPlace/Sites.cpp
	InPlace/Unique.cpp
	InPlace/UniqueResults.cpp
	InPlace/Versions.cpp
	InPlace/Writer.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrEffects
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRCallInterfaces
	MLIRControlFlowInterfaces
	MLIRInferTypeOpInterface
	MLIRLoopLikeInterface
)

# idr-rc-exclusive and idr-knots.
add_mlir_library(IdrOwnership
	Ownership/Exclusive.cpp
	Ownership/Knots.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrEffects
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRControlFlowInterfaces
	MLIRInferTypeOpInterface
	MLIRLoopLikeInterface
)

# idr-structure-loops and idr-ordered-loops: an array's loops as
# linalg.generic and scf; and an op of the generating set, or an element's
# update, whose region calls into its function's own cycle, split into
# join points where frames can take it apart.
add_mlir_library(IdrStructureLoops
	StructureLoops/Forms.cpp
	StructureLoops/JoinLoops.cpp
	StructureLoops/Linalg.cpp
	StructureLoops/Lowering.cpp
	StructureLoops/StructureLoops.cpp
	StructureLoops/Updates.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrJoins
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRTransformUtils
	MLIRCallInterfaces
	MLIRDestinationStyleOpInterface
	MLIRValueBoundsOpInterface
	MLIRAffineDialect
	MLIRArithDialect
	MLIRLinalgDialect
	MLIRSCFDialect
	MLIRSCFTransforms
	MLIRTensorDialect
	MLIRArithUtils
	MLIRUBDialect
	MLIRDialectUtils
)

# idr-accumulate, idr-trmc, idr-frames and idr-tail-loops: a call in tail
# position never grows the stack, and a recursion's depth lives on frame
# stacks, its frames bounded by counting's bound.
add_mlir_library(IdrTail
	Tail/Accumulate.cpp
	Tail/AccumulatorPlan.cpp
	Tail/ComponentLifetimes.cpp
	Tail/Continuations.cpp
	Tail/Dissolve.cpp
	Tail/Frames.cpp
	Tail/FramesFamily.cpp
	Tail/Jumps.cpp
	Tail/Outline.cpp
	Tail/Split.cpp
	Tail/TailLoops.cpp
	Tail/Trmc.cpp
	Tail/TrmcRewrite.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrCounting
	IdrEffects
	IdrJoins
	IdrSolver
	IdrStructureLoops
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRAnalysis
	MLIRRewrite
	MLIRTransformUtils
	MLIRControlFlowInterfaces
	MLIRSideEffectInterfaces
	MLIRFuncDialect
	MLIRSCFDialect
	MLIRSCFTransforms
	MLIRArithDialect
	MLIRUBDialect
)

# idr-narrow, with the word rewrite it nests, which the specification's
# pipeline pairs with it as its apply group (Generated/ApplyGroups.h.inc),
# and idr-narrow-lanes.
add_mlir_library(IdrNarrow
	Narrow/Carried.cpp
	Narrow/Copy.cpp
	Narrow/Facts.cpp
	Narrow/Lanes.cpp
	Narrow/Narrow.cpp
	Narrow/Ops.cpp
	Narrow/Versions.cpp
	Narrow/Widths.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRSupport
	MLIRPass
	MLIRAnalysis
	MLIRRewrite
	MLIRTransformUtils
	MLIRDialectUtils
	MLIRCastInterfaces
	MLIRControlFlowInterfaces
	MLIRInferIntRangeInterface
	MLIRSideEffectInterfaces
	MLIRValueBoundsOpInterface
	MLIRArithDialect
	MLIRArithTransforms
	MLIRFuncDialect
	MLIRSCFDialect
	MLIRUBDialect
	MLIRVectorDialect
)

# idr-bufferize: One-Shot bufferization of every idr.func, with the
# bufferization models of the dialect's ops, its alias classes the solver
# layer's components.
add_mlir_library(IdrBufferize
	Bufferize/Bufferize.cpp
	Bufferize/Data.cpp
	Bufferize/Generating.cpp
	Bufferize/Linear.cpp
	Bufferize/Releases.cpp
	Bufferize/Values.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRArithDialect
	MLIRBufferizationDialect
	MLIRBufferizationTransforms
	MLIRDestinationStyleOpInterface
	MLIRDialectUtils
	MLIRMemRefDialect
	MLIRCallInterfaces
	MLIRTensorDialect
	MLIRLinalgDialect
	MLIRUBDialect
	MLIRFunctionInterfaces
	MLIRControlFlowInterfaces
)

# idr-columns: an array of records as one array per field, by upstream's
# one-to-N type conversion, before the array ops are lowered.
add_mlir_library(IdrColumns
	Columns/ArrayOps.cpp
	Columns/Calls.cpp
	Columns/Columns.cpp
	Columns/Records.cpp
	Columns/Tensors.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrStructureLoops
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRTransformUtils
	MLIRSCFDialect
	MLIRSCFTransforms
	MLIRTensorDialect
	MLIRArithDialect
	MLIRUBDialect
)

# idr-expect: the named properties tests state, as the table the tests'
# records print (ExpectProperties.inc).
add_mlir_library(IdrExpect
	Expect/Accesses.cpp
	Expect/Allocation.cpp
	Expect/Arguments.cpp
	Expect/BuildsNothing.cpp
	Expect/Calls.cpp
	Expect/Clones.cpp
	Expect/ConstantStack.cpp
	Expect/Continuations.cpp
	Expect/CountsNothing.cpp
	Expect/CrashSites.cpp
	Expect/Cycles.cpp
	Expect/Expect.cpp
	Expect/Folded.cpp
	Expect/Guards.cpp
	Expect/InPlace.cpp
	Expect/LabelsLeast.cpp
	Expect/Lookup.cpp
	Expect/MovesOut.cpp
	Expect/Named.cpp
	Expect/NarrowedLanes.cpp
	Expect/NotCalled.cpp
	Expect/Quantities.cpp
	Expect/Reached.cpp
	Expect/Report.cpp
	Expect/ResetsUnshared.cpp
	Expect/ReusesEveryCell.cpp
	Expect/ReusesInPlace.cpp
	Expect/Stages.cpp
	Expect/StructuredLoops.cpp
	Expect/TestsNothing.cpp
	Expect/Vectorized.cpp
	Expect/Words.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrNarrow
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRParser
	MLIRCallInterfaces
	MLIRCastInterfaces
	MLIRFunctionInterfaces
	MLIRInferIntRangeInterface
	MLIRLoopLikeInterface
	MLIRSideEffectInterfaces
	MLIRFuncDialect
	MLIRArithDialect
	MLIRMathDialect
	MLIRUBDialect
	MLIRMemRefDialect
	MLIRSCFDialect
	MLIRLLVMDialect
	MLIRLinalgDialect
	MLIRTensorDialect
	MLIRVectorDialect
)

# The contracts idris-mlir-opt --idr-contracts checks after every pass on
# the module or the program, idr-expect's definitions among them, and the
# pass that breaks one on purpose for their test.
add_mlir_library(IdrContracts
	Contracts/Contracts.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrEffects
	IdrExpect
	IdrSolver
	MLIRIR
	MLIRPass
	MLIRSupport
)

# The pipeline idris-mlir runs and the tools register, printed from the
# specification's one list (Generated/Pipeline.h.inc): every pass of ours
# by its generated constructor, each area's library that defines one, the
# steps that widen and write the rows around a nest, and upstream's passes
# it names.
add_mlir_library(IdrPipeline
	Pipeline.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrBufferize
	IdrColumns
	IdrConversion
	IdrCounting
	IdrDeduplicate
	IdrDefunctionalize
	IdrEGraph
	IdrEffects
	IdrExpect
	IdrInPlace
	IdrInline
	IdrLifetimes
	IdrNarrow
	IdrOptimize
	IdrOwnership
	IdrSpecialize
	IdrStructureLoops
	IdrTail
	IdrTarget
	IdrIR
	IdrSolver
	MLIRFuncDialect
	MLIRPass
	MLIRTransforms
	MLIRLinalgTransforms
	MLIRBufferizationTransforms
	MLIRTransformDialectTransforms
	MLIRLLVMIRTransforms
	MLIRVectorToSCF
	MLIRMemRefTransforms
	MLIRAffineToStandard
	MLIRSCFToControlFlow
	MLIRVectorToLLVMPass
	MLIRConvertToLLVMPass
	MLIRReconcileUnrealizedCasts
)
