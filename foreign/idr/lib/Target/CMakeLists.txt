# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The target, decided once: idr-target and what passes read of it (the
# width of its vectors), the schedule library that vectorizes by it, what
# LLVM says of it (its machine and the optimization pipeline), the
# partition of the program into the objects code is generated for, and the
# bins those objects are, named as the lowering mangles them. The triple
# and CPUs are the target entry's (idr/TargetEntry.h).
add_mlir_library(IdrTarget
	Bins.cpp
	Extract.cpp
	Optimize.cpp
	Partition.cpp
	Schedules.cpp
	Target.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrOpsIncGen
	IdrPassesIncGen
	IdrScheduleOpsIncGen

	LINK_LIBS PUBLIC
	IdrConversion
	IdrIR
	IdrSolver
	IdrSupport
	MLIRIR
	MLIRPass
	MLIRTransformDialect
	MLIRTransformDialectInterfaces
	MLIRAffineDialect
	MLIRArithDialect
	MLIRDialectUtils
	MLIRFunctionInterfaces
	MLIRLinalgDialect
	MLIRLinalgTransformOps
	MLIRLinalgTransforms
	MLIRLinalgUtils
	MLIRMemRefDialect
	MLIRSCFDialect
	MLIRSCFTransforms
	MLIRSideEffectInterfaces
	MLIRVectorDialect
	MLIRVectorTransformOps
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
