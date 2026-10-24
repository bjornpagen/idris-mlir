# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The dialect's libraries, in dependency order: the support every library
# may use, the dialect, the solver layer and the analyses, the target, the
# lowering, the passes and the pipeline, and the driver idris-mlir is. A
# library links exactly the libraries whose headers it includes and those
# that define the pass constructors it declares; a header of templates
# alone, or one only its own library implements, asks for no link. Every
# library but the support links the dialect, and so reuses its precompiled
# header (IR/CMakeLists.txt).
add_subdirectory(Support)
add_subdirectory(IR)
add_subdirectory(Analysis)
add_subdirectory(Target)

# idr-lower, idr-entry and idr-tail-calls, with the patterns of the
# conversion to func, arith, scf, ub and llvm and the runtime's calls; the
# lowering of a function's values, regions, lifetimes and counts
# (Conversion/Lower), which accounts a frame by counting's bound.
add_mlir_library(IdrConversion
	Conversion/Arrays.cpp
	Conversion/Bigs.cpp
	Conversion/Buffers.cpp
	Conversion/Cells.cpp
	Conversion/Checks.cpp
	Conversion/Descriptors.cpp
	Conversion/Elements.cpp
	Conversion/Entry.cpp
	Conversion/Lower.cpp
	Conversion/Lower/Accounts.cpp
	Conversion/Lower/Attributes.cpp
	Conversion/Lower/Counting.cpp
	Conversion/Lower/Destinations.cpp
	Conversion/Lower/Drops.cpp
	Conversion/Lower/Functions.cpp
	Conversion/Lower/Lifetimes.cpp
	Conversion/Lower/Packages.cpp
	Conversion/Lower/Regions.cpp
	Conversion/Lower/Repack.cpp
	Conversion/Lower/Rooms.cpp
	Conversion/Lower/Statics.cpp
	Conversion/Lower/Values.cpp
	Conversion/Mangle.cpp
	Conversion/Matches.cpp
	Conversion/MemoCells.cpp
	Conversion/Memrefs.cpp
	Conversion/Movements.cpp
	Conversion/PassThroughMemory.cpp
	Conversion/ReturnRegisters.cpp
	Conversion/Runtime.cpp
	Conversion/RuntimeCalls.cpp
	Conversion/RuntimeCells.cpp
	Conversion/Scalars.cpp
	Conversion/StaticBytes.cpp
	Conversion/StaticData.cpp
	Conversion/Strings.cpp
	Conversion/TailCalls.cpp
	Conversion/Words.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrCounting
	IdrEffects
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRSupport
	MLIRPass
	MLIRAnalysis
	MLIRRewrite
	MLIRTransformUtils
	MLIRControlFlowInterfaces
	MLIRDataLayoutInterfaces
	MLIRFunctionInterfaces
	MLIRInferIntRangeInterface
	MLIRSideEffectInterfaces
	MLIRDialectUtils
	MLIRFuncDialect
	MLIRFuncTransforms
	MLIRArithDialect
	MLIRMathDialect
	MLIRSCFDialect
	MLIRSCFTransforms
	MLIRSCFToControlFlow
	MLIRControlFlowDialect
	MLIRUBDialect
	MLIRAffineDialect
	MLIRMemRefDialect
	MLIRMemRefTransforms
	MLIRMemRefUtils
	MLIRLinalgDialect
	MLIRLLVMDialect
	# The memref descriptor an array's view is.
	MLIRLLVMCommonConversion
	MLIRMemRefToLLVM
	# The math ops no fold reaches, which become LLVM's intrinsics.
	MLIRMathToLLVM
	# How the target returns a result: LLVM's types and target machine.
	MLIRTargetLLVMIRExport
	MLIRTargetLLVMIRTransforms
)

add_subdirectory(Transforms)

# idris-mlir: the compilation (the frontend, one pass manager, LLVM), the
# runtime's preparation, the stack a program takes, on the solver layer's
# graphs, and the link. It reads the runtime's C ABI (idris_rt.h, the
# reserved-stack runner), whose include directory idris_rt gives, and the
# target entry's description and link flags (idr/TargetEntry.h,
# generated).
add_mlir_library(IdrDriver
	Driver/Artifacts.cpp
	Driver/Compile.cpp
	Driver/LinkRuntime.cpp
	Driver/Main.cpp
	Driver/Options.cpp
	Driver/Outcome.cpp
	Driver/Prepare.cpp
	Driver/ReadRuntime.cpp
	Driver/Register.cpp
	Driver/Run.cpp
	Driver/StackBound.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrPipeline
	IdrContracts
	IdrConversion
	IdrExpect
	IdrTarget
	IdrIR
	IdrSolver
	IdrSupport
	idris_rt
	MLIRIR
	MLIRSupport
	MLIRParser
	MLIRPass
	# The action handlers: debug counters, action logging.
	MLIRDebug
	MLIRTargetLLVMIRExport
	MLIRBuiltinToLLVMIRTranslation
	MLIRTensorDialect
	MLIRSCFDialect
	MLIRLLVMToLLVMIRTranslation
	MLIRArithDialect
	MLIRMathDialect
	MLIRUBDialect
	MLIRMemRefDialect
	MLIRLLVMDialect
	# What the compiler registers (Driver/Register.cpp, registerCompiler): the dialects
	# its pipeline reaches, their external models and the passes it runs.
	MLIRFuncDialect
	MLIRControlFlowDialect
	MLIRLinalgDialect
	MLIRBufferizationDialect
	MLIRAffineDialect
	MLIRVectorDialect
	MLIRTransformDialect
	MLIRDLTIDialect
	MLIRArithTransforms
	MLIRArithValueBoundsOpInterfaceImpl
	MLIRBufferizationTransforms
	MLIRLinalgTransforms
	MLIRSCFTransforms
	MLIRTensorTransforms
	MLIRTensorInferTypeOpInterfaceImpl
	MLIRCastInterfaces
	MLIRFuncInlinerExtension
	MLIRLLVMIRTransforms
	MLIRArithToLLVM
	MLIRComplexToLLVM
	MLIRControlFlowToLLVM
	MLIRFuncToLLVM
	MLIRIndexToLLVM
	MLIRMathToLLVM
	MLIRMemRefToLLVM
	MLIRUBToLLVM
	MLIRVectorToLLVM
	MLIRLinalgTransformOps
	MLIRVectorTransformOps
	MLIRTransforms
	MLIRTransformDialectTransforms
	MLIRVectorToSCF
	MLIRMemRefTransforms
	MLIRAffineToStandard
	MLIRSCFToControlFlow
	MLIRVectorToLLVMPass
	MLIRConvertToLLVMPass
	MLIRReconcileUnrealizedCasts
	LLVMObject
	LLVMBitReader
	LLVMBitWriter
	${IDR_LLVM_CODEGEN_LIBS}
)
target_compile_definitions(IdrDriver PRIVATE ${IDR_DRIVER_DEFINITIONS})
