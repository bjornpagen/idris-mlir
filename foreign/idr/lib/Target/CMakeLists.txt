# The target, decided once: idr-target and what passes read of it (the
# width of its vectors), and what LLVM says of it (its machine and the
# optimization pipeline). The triple and CPU are the target entry's.
add_mlir_library(IdrTarget
	Target.cpp
	Optimize.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	DEPENDS
	IdrPassesIncGen

	LINK_LIBS PUBLIC
	MLIRIR
	MLIRPass
	MLIRLLVMDialect
	MLIRDLTIDialect
	MLIRTargetLLVMIRImport
	MLIRTargetLLVMIRTransforms
	${IDR_LLVM_CODEGEN_LIBS}
)
target_compile_definitions(IdrTarget PRIVATE ${IDR_TARGET_DEFINITIONS})
