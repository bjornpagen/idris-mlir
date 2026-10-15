# The passes: one library per area, and the pipeline that orders them.
# LLVM's build checks that a directory's library lists every .cpp in it;
# here the areas share the directory with the pipeline, whose library comes
# last and checks the whole, and each area's says it lists only its own
# (PARTIAL_SOURCES_INTENDED).

# idr-effects: the effects of every function and call, from the Effects
# analysis; idr-constants: the constants each function's summary proves.
add_mlir_library(IdrEffects
	Effects/Effects.cpp
	Effects/Constants.cpp

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
	MLIRAnalysis
	MLIRTransformUtils
	MLIRSideEffectInterfaces
	MLIRArithDialect
)

# The inline step: upstream's inliner by MLton's rule on the callee's final size.
add_mlir_library(IdrInline
	Inline/Inline.cpp

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

# The specialization nodes, raising and idr-redirect: the calls of a node's key.
add_mlir_library(IdrSpecialize
	Specialize/Specialize.cpp
	Specialize/Specialization.cpp
	Specialize/Keys.cpp
	Specialize/Consumer.cpp
	Specialize/Raise.cpp
	Specialize/Redirect.cpp
	Specialize/RedirectPass.cpp
	Specialize/Patterns.cpp
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
	IdrSmallPasses
	MLIRIR
	MLIRPass
	MLIRAnalysis
	MLIRParser
	MLIRRewrite
	MLIRTransformUtils
	MLIRArithDialect
)

# idr-stack, idr-identity, idr-demand and idr-deduplicate.
add_mlir_library(IdrSmallPasses
	Stack/Stack.cpp
	Identity/Identity.cpp
	Demand/Demand.cpp
	Deduplicate/EliminateDuplicateFunctions.cpp
	Deduplicate/Equivalence.cpp

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

# idr-optimize, the ready set over the call graph's components, and
# idr-contify. It links the libraries whose steps a function's pipeline runs.
add_mlir_library(IdrOptimize
	Optimize/Optimize.cpp
	Optimize/ReadySet.cpp
	Optimize/Component.cpp
	Optimize/Waves.cpp
	Optimize/Contify.cpp
	Optimize/PureCalls.cpp

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
	MLIRAnalysis
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
	Defunctionalize/Forces.cpp

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
	Ownership/Buffers.cpp
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
	MLIRMemRefDialect
	MLIRLinalgDialect
	MLIRLinalgTransforms
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
	MLIRAnalysis
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

# idr-bufferize: One-Shot bufferization of every idr.func, with the
# bufferization models of the dialect's ops.
add_mlir_library(IdrBufferize
	Bufferize/Bufferize.cpp
	Bufferize/Releases.cpp
	Bufferize/Linear.cpp
	Bufferize/Data.cpp
	Bufferize/Values.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	MLIRIR
	MLIRPass
	MLIRBufferizationDialect
	MLIRBufferizationTransforms
	MLIRMemRefDialect
	MLIRCallInterfaces
	MLIRTensorDialect
	MLIRLinalgDialect
	MLIRUBDialect
	MLIRFunctionInterfaces
	MLIRControlFlowInterfaces
)

# idr-structure-loops: an array's loops as linalg.generic and scf.
add_mlir_library(IdrStructureLoops
	StructureLoops/StructureLoops.cpp
	StructureLoops/Forms.cpp
	StructureLoops/Linalg.cpp
	StructureLoops/Lowering.cpp
	StructureLoops/Nests.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	MLIRIR
	MLIRPass
	MLIRTransformUtils
	MLIRValueBoundsOpInterface
	MLIRArithDialect
	MLIRLinalgDialect
	MLIRSCFDialect
	MLIRTensorDialect
	MLIRArithUtils
	MLIRUBDialect
	MLIRDialectUtils
)

# idr-columns: an array of records as one array per field, by upstream's
# one-to-N type conversion, before the array ops are lowered.
add_mlir_library(IdrColumns
	Columns/Columns.cpp
	Columns/Calls.cpp
	Columns/Tensors.cpp
	Columns/ArrayOps.cpp
	Columns/Records.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrStructureLoops
	MLIRIR
	MLIRPass
	MLIRTransformUtils
	MLIRSCFDialect
	MLIRSCFTransforms
	MLIRTensorDialect
	MLIRArithDialect
	MLIRUBDialect
)

# idr-expect: the named properties tests state.
add_mlir_library(IdrExpect
	Expect/Expect.cpp
	Expect/Lookup.cpp
	Expect/Report.cpp
	Expect/Named.cpp
	Expect/Cycles.cpp
	Expect/Allocation.cpp
	Expect/Apart.cpp
	Expect/Arguments.cpp
	Expect/ByName.cpp
	Expect/Calls.cpp
	Expect/Clones.cpp
	Expect/Closures.cpp
	Expect/ComputesNothing.cpp
	Expect/ConstantStack.cpp
	Expect/Continuations.cpp
	Expect/CountedLoop.cpp
	Expect/CountsNothing.cpp
	Expect/CrashSites.cpp
	Expect/DimsKnown.cpp
	Expect/Does.cpp
	Expect/Facts.cpp
	Expect/Folds.cpp
	Expect/Fused.cpp
	Expect/Growth.cpp
	Expect/Guards.cpp
	Expect/InPlace.cpp
	Expect/LinkerNames.cpp
	Expect/Lowered.cpp
	Expect/Memory.cpp
	Expect/MovesOut.cpp
	Expect/NarrowedLanes.cpp
	Expect/NotCalled.cpp
	Expect/Output.cpp
	Expect/Paths.cpp
	Expect/Placement.cpp
	Expect/Proved.cpp
	Expect/Quantities.cpp
	Expect/Reaches.cpp
	Expect/ResetsUnshared.cpp
	Expect/Returns.cpp
	Expect/ReusesEveryCell.cpp
	Expect/ReusesInPlace.cpp
	Expect/Signature.cpp
	Expect/Sizes.cpp
	Expect/SolvedEffects.cpp
	Expect/Stage.cpp
	Expect/StructuredLoops.cpp
	Expect/TestsNothing.cpp
	Expect/TypedReads.cpp
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
	IdrNarrow
	IdrBufferize
	IdrStructureLoops
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
	IdrOptimize
	IdrInline
	IdrSpecialize
	IdrDefunctionalize
	IdrOwnership
	IdrTail
	IdrNarrow
	IdrBufferize
	IdrStructureLoops
	IdrColumns
	IdrSmallPasses
	IdrExpect
	IdrEffects
	IdrConversion
	IdrTarget
	IdrIR
	MLIRFuncDialect
	MLIRPass
	MLIRTransforms
	MLIRLinalgTransforms
	MLIRBufferizationTransforms
	MLIRTransformDialectTransforms
	MLIRVectorToSCF
	MLIRMemRefTransforms
	MLIRAffineToStandard
	MLIRSCFToControlFlow
	MLIRVectorToLLVMPass
	MLIRConvertToLLVMPass
	MLIRReconcileUnrealizedCasts
)
