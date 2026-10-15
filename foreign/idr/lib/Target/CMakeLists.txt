# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The target, decided once: idr-target and what passes read of it (the
# width of its vectors), the schedule library that vectorizes by it, what
# LLVM says of it (its machine and the optimization pipeline) and the
# partition of the program into the objects code is generated for. The
# triple and CPU are the target entry's.
add_mlir_library(IdrTarget
	Target.cpp
	Optimize.cpp
	Schedules.cpp
	Partition.cpp
	Extract.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen
	IdrScheduleOpsIncGen

	LINK_LIBS PUBLIC
	IdrIR
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRParser
	MLIRTransformDialect
	MLIRTransformDialectInterfaces
	MLIRLinalgDialect
	MLIRLinalgTransforms
	MLIRSCFDialect
	MLIRSCFTransforms
	MLIRVectorDialect
	MLIRTilingInterface
	MLIRDataLayoutInterfaces
	MLIRLLVMDialect
	MLIRDLTIDialect
	MLIRTargetLLVMIRImport
	MLIRTargetLLVMIRTransforms
	LLVMAnalysis
	LLVMBitReader
	LLVMBitWriter
	${IDR_LLVM_CODEGEN_LIBS}
)
target_compile_definitions(IdrTarget PRIVATE ${IDR_TARGET_DEFINITIONS})
