# The passes: one library per area, and the pipeline that orders them.
# LLVM's build checks that a directory's library lists every .cpp in it;
# here the areas share the directory with the pipeline, whose library comes
# last and checks the whole, and each area's says it lists only its own
# (PARTIAL_SOURCES_INTENDED).

# idr-effects: the effects of every function and call, from the Effects analysis.
add_mlir_library(IdrEffects
	Effects/Effects.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	MLIRIR
	MLIRPass
)

# idr-inline: the force preparation, then upstream's inliner by MLton's rule.
add_mlir_library(IdrInline
	Inline/Inline.cpp
	Inline/Prepare.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	MLIRIR
	MLIRPass
	MLIRAnalysis
	MLIRTransforms
	MLIRTransformUtils
)

# idr-specialize and idr-redirect: raising, cloning and the calls of a clone's key.
add_mlir_library(IdrSpecialize
	Specialize/Specialize.cpp
	Specialize/Specialization.cpp
	Specialize/Keys.cpp
	Specialize/Consumer.cpp
	Specialize/Raise.cpp
	Specialize/Redirect.cpp
	Specialize/RedirectPass.cpp
	Specialize/Patterns.cpp
	Specialize/Clones.cpp
	Specialize/Report.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRRewrite
	MLIRTransformUtils
	MLIRArithDialect
)

# idr-stack, idr-identity, idr-isolate and idr-demand.
add_mlir_library(IdrSmallPasses
	Stack/Stack.cpp
	Identity/Identity.cpp
	Isolate/Isolate.cpp
	Demand/Demand.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	MLIRIR
	MLIRPass
	MLIRTransformUtils
	MLIRArithDialect
	MLIRLLVMDialect
)

# idr-simplify, its round and its instrumentation; idr-round-facts, idr-loop-breakers
# and idr-contify. It links the libraries whose constructors the round calls.
add_mlir_library(IdrSimplify
	Simplify/Simplify.cpp
	Simplify/Round.cpp
	Simplify/RoundFacts.cpp
	Simplify/LoopBreakers.cpp
	Simplify/Contify.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrSupport
	IdrEffects
	IdrSmallPasses
	IdrInline
	IdrSpecialize
	MLIRIR
	MLIRPass
	MLIRTransforms
	MLIRTransformUtils
	MLIRArithTransforms
)

# idr-defunctionalize, as one dialect conversion of the module.
add_mlir_library(IdrDefunctionalize
	Defunctionalize/Pass.cpp
	Defunctionalize/Keys.cpp
	Defunctionalize/Moves.cpp
	Defunctionalize/Decide.cpp
	Defunctionalize/Declare.cpp
	Defunctionalize/Converter.cpp
	Defunctionalize/Patterns.cpp
	Defunctionalize/PatternsCalls.cpp
	Defunctionalize/ByName.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRTransformUtils
	MLIRUBDialect
)

# idr-rc, with its nested steps idr-rc-place and idr-rc-commit, which it builds.
add_mlir_library(IdrOwnership
	Ownership/Rc.cpp
	Ownership/Signatures.cpp
	Ownership/Share.cpp
	Ownership/Specialize.cpp
	Ownership/Place.cpp
	Ownership/Reuse.cpp
	Ownership/Take.cpp
	Ownership/Classes.cpp
	Ownership/Reshape.cpp
	Ownership/Placement.cpp
	Ownership/Commit.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	MLIRIR
	MLIRPass
	MLIRSideEffectInterfaces
	MLIRArithDialect
	MLIRUBDialect
)

# idr-accumulate, idr-trmc, idr-tail-loops and idr-returned-arguments.
add_mlir_library(IdrTail
	Tail/Accumulate.cpp
	Tail/AccumulatorPlan.cpp
	Tail/Trmc.cpp
	Tail/TailLoops.cpp
	Tail/WhileDo.cpp
	Tail/Loop.cpp
	Tail/Returned.cpp
	Tail/ReturnedArguments.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	MLIRIR
	MLIRPass
	MLIRRewrite
	MLIRTransformUtils
	MLIRSideEffectInterfaces
	MLIRFuncDialect
	MLIRSCFDialect
	MLIRSCFTransforms
	MLIRArithDialect
	MLIRUBDialect
)

# idr-narrow, with its nested word rewrite, and idr-narrow-lanes.
add_mlir_library(IdrNarrow
	Narrow/Facts.cpp
	Narrow/Carried.cpp
	Narrow/Ops.cpp
	Narrow/Versions.cpp
	Narrow/Narrow.cpp
	Narrow/Widths.cpp
	Narrow/Copy.cpp
	Narrow/Lanes.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
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

# idr-in-bounds, with its nested proofs, and the Lengths it proves with.
add_mlir_library(IdrInBounds
	InBounds/InBounds.cpp
	InBounds/Prove.cpp
	InBounds/Lengths.cpp
	InBounds/Relation.cpp
	InBounds/Clamps.cpp
	InBounds/Joins.cpp
	InBounds/Returned.cpp
	InBounds/Guards.cpp
	InBounds/System.cpp
	InBounds/Paths.cpp
	InBounds/Induction.cpp
	InBounds/Quotients.cpp
	InBounds/Masks.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	MLIRIR
	MLIRSupport
	MLIRPass
	MLIRPresburger
	MLIRControlFlowInterfaces
	MLIRFunctionInterfaces
	MLIRInferIntRangeInterface
	MLIRSCFDialect
	MLIRArithDialect
	MLIRMemRefDialect
	MLIRUBDialect
)

# idr-vectorize, on each func.func after lowering.
add_mlir_library(IdrVectorize
	Vectorize/Vectorize.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrTarget
	MLIRIR
	MLIRPass
	MLIRRewrite
	MLIRTransformUtils
	MLIRTilingInterface
	MLIRFuncDialect
	MLIRAffineDialect
	MLIRArithDialect
	MLIRLinalgDialect
	MLIRLinalgTransforms
	MLIRLinalgUtils
	MLIRMemRefDialect
	MLIRSCFDialect
	MLIRSCFTransforms
	MLIRVectorDialect
	MLIRVectorTransforms
)

# idr-expect: the named properties tests state.
add_mlir_library(IdrExpect
	Expect/Expect.cpp
	Expect/Lookup.cpp
	Expect/Report.cpp
	Expect/Named.cpp
	Expect/Cycles.cpp
	Expect/Allocation.cpp
	Expect/BreaksLast.cpp
	Expect/CellsFit.cpp
	Expect/Clones.cpp
	Expect/Closures.cpp
	Expect/ConstantStack.cpp
	Expect/Continuations.cpp
	Expect/CountedLoop.cpp
	Expect/CountsNothing.cpp
	Expect/EveryCycleHasBreaker.cpp
	Expect/Facts.cpp
	Expect/Folds.cpp
	Expect/InBounds.cpp
	Expect/MovesOut.cpp
	Expect/NarrowedLanes.cpp
	Expect/NotCalled.cpp
	Expect/Output.cpp
	Expect/PureArrayLoops.cpp
	Expect/Quantities.cpp
	Expect/ResetsUnshared.cpp
	Expect/ReusesEveryCell.cpp
	Expect/ReusesInPlace.cpp
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
	IdrSupport
	IdrInBounds
	IdrNarrow
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
	MLIRVectorDialect
)

# The pipeline idris-mlir runs and the tools register: every pass the .td
# declares, by its generated constructor, and upstream's lowering passes.
add_mlir_library(IdrPipeline
	Pipeline.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrSimplify
	IdrInline
	IdrSpecialize
	IdrDefunctionalize
	IdrOwnership
	IdrTail
	IdrNarrow
	IdrInBounds
	IdrSmallPasses
	IdrVectorize
	IdrExpect
	IdrEffects
	IdrConversion
	IdrTarget
	IdrIR
	MLIRFuncDialect
	MLIRPass
	MLIRTransforms
	MLIRLinalgTransforms
	MLIRVectorToSCF
	MLIRMemRefTransforms
	MLIRAffineToStandard
	MLIRSCFToControlFlow
	MLIRVectorToLLVMPass
	MLIRConvertToLLVMPass
	MLIRReconcileUnrealizedCasts
)
