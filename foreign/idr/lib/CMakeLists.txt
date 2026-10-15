# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The dialect's libraries, in dependency order: the support every library
# may use, the dialect, its analyses, the target, the lowering, the passes
# and the pipeline, and the driver idris-mlir is. A library links exactly
# the libraries whose headers it includes and those that define the pass
# constructors it declares.
add_subdirectory(Support)
add_subdirectory(IR)
add_subdirectory(Analysis)
add_subdirectory(Target)

# idr-lower, idr-entry and idr-tail-calls, with the patterns of the
# conversion to func, arith, scf, ub and llvm and the runtime's calls.
add_mlir_library(IdrConversion
	Conversion/Mangle.cpp
	Conversion/FuncToFunc.cpp
	Conversion/Lower.cpp
	Conversion/Facts.cpp
	Conversion/Matches.cpp
	Conversion/Words.cpp
	Conversion/Runtime.cpp
	Conversion/RuntimeCells.cpp
	Conversion/StaticData.cpp
	Conversion/StaticNames.cpp
	Conversion/Cells.cpp
	Conversion/Counting.cpp
	Conversion/Fields.cpp
	Conversion/MemoCells.cpp
	Conversion/Arrays.cpp
	Conversion/Descriptors.cpp
	Conversion/Elements.cpp
	Conversion/Memrefs.cpp
	Conversion/Buffers.cpp
	Conversion/Bigs.cpp
	Conversion/Strings.cpp
	Conversion/Scalars.cpp
	Conversion/Checks.cpp
	Conversion/RuntimeCalls.cpp
	Conversion/Entry.cpp
	Conversion/TailCallPlan.cpp
	Conversion/TailPosition.cpp
	Conversion/Frame.cpp
	Conversion/ReturnRegisters.cpp
	Conversion/TailCalls.cpp
	Conversion/PassThroughMemory.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrAnalysis
	IdrSupport
	MLIRIR
	MLIRSupport
	MLIRPass
	MLIRAnalysis
	MLIRTransformUtils
	MLIRControlFlowInterfaces
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
	# How the target returns a result: LLVM's types and target machine.
	MLIRTargetLLVMIRExport
	MLIRTargetLLVMIRTransforms
)

add_subdirectory(Transforms)

# idris-mlir: the compilation (the frontend, one pass manager, LLVM), the
# runtime's preparation and the link. It reads the runtime's C ABI
# (idris_rt.h, the reserved-stack runner) and the target entry's list of
# processor features (cpu_features.h), whose include directory idris_rt
# gives, and the target entry's link flags (idr/TargetEntry.h, generated).
add_mlir_library(IdrDriver
	Driver/Artifacts.cpp
	Driver/Compile.cpp
	Driver/LinkRuntime.cpp
	Driver/Main.cpp
	Driver/Options.cpp
	Driver/Prepare.cpp
	Driver/ReadRuntime.cpp
	Driver/Run.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	IdrPipeline
	IdrTarget
	IdrIR
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
	MLIRRegisterAllDialects
	MLIRRegisterAllExtensions
	MLIRRegisterAllPasses
	MLIRArithDialect
	MLIRMathDialect
	MLIRUBDialect
	MLIRMemRefDialect
	MLIRLLVMDialect
	LLVMObject
	LLVMBitReader
	LLVMBitWriter
	${IDR_LLVM_CODEGEN_LIBS}
)
target_compile_definitions(IdrDriver PRIVATE ${IDR_DRIVER_DEFINITIONS} ${IDR_TARGET_DEFINITIONS})
