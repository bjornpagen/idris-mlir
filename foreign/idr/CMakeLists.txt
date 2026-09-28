# The idr dialect, its passes and tools (TC-ZONE-1). Everything here faces the
# MLIR C++ API, so it is quarantine code: headers, TableGen, inheritance.
# PIN(mlir-cxx-api) — see PINS.md

find_package(MLIR REQUIRED CONFIG)
list(APPEND CMAKE_MODULE_PATH "${MLIR_CMAKE_DIR}" "${LLVM_CMAKE_DIR}")
include(TableGen)
include(AddLLVM)
include(AddMLIR)

# TableGen reads the directory's include path.
include_directories(SYSTEM ${LLVM_INCLUDE_DIRS} ${MLIR_INCLUDE_DIRS})
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

set(LLVM_TARGET_DEFINITIONS ${CMAKE_CURRENT_SOURCE_DIR}/include/idr/IdrOps.td)
mlir_tablegen(include/idr/IdrDialect.h.inc -gen-dialect-decls -dialect=idr)
mlir_tablegen(include/idr/IdrDialect.cc.inc -gen-dialect-defs -dialect=idr)
mlir_tablegen(include/idr/IdrTypes.h.inc -gen-typedef-decls -typedefs-dialect=idr)
mlir_tablegen(include/idr/IdrTypes.cc.inc -gen-typedef-defs -typedefs-dialect=idr)
mlir_tablegen(include/idr/IdrAttrs.h.inc -gen-attrdef-decls -attrdefs-dialect=idr)
mlir_tablegen(include/idr/IdrAttrs.cc.inc -gen-attrdef-defs -attrdefs-dialect=idr)
mlir_tablegen(include/idr/IdrEnums.h.inc -gen-enum-decls)
mlir_tablegen(include/idr/IdrEnums.cc.inc -gen-enum-defs)
mlir_tablegen(include/idr/IdrOps.h.inc -gen-op-decls)
mlir_tablegen(include/idr/IdrOps.cc.inc -gen-op-defs)
mlir_tablegen(include/idr/IdrInterfaces.h.inc -gen-op-interface-decls)
mlir_tablegen(include/idr/IdrInterfaces.cc.inc -gen-op-interface-defs)
set(LLVM_TARGET_DEFINITIONS ${CMAKE_CURRENT_SOURCE_DIR}/include/idr/Passes.td)
mlir_tablegen(include/idr/Passes.h.inc -gen-pass-decls -name Idr)
set(LLVM_TARGET_DEFINITIONS ${CMAKE_CURRENT_SOURCE_DIR}/lib/Dialect/Canonicalize.td)
mlir_tablegen(include/idr/IdrCanonicalize.inc -gen-rewriters)
add_public_tablegen_target(idr_tablegen)

# idris-mlir-cc links the runtime's bitcode into the program (Linker,
# BitReader, Object) and internalizes it (IPO), TC-LINK-1; idr-eval compiles
# with ORC's LLJIT (OrcJIT) and the same pipeline (Passes).
llvm_map_components_to_libnames(IDR_LLVM_CODEGEN_LIBS nativecodegen passes linker bitreader object ipo orcjit)

add_library(idr_dialect STATIC
	lib/Dialect/Canonicalize.cc
	lib/Dialect/Dialect.cc
	lib/Dialect/Effects.cc
	lib/Dialect/Ops.cc
	lib/Eval/Child.cc
	lib/Eval/Eval.cc
	lib/Eval/Jit.cc
	lib/Eval/Reify.cc
	lib/Lower.cc
	lib/Lower/Layout.cc
	lib/Lower/Matches.cc
	lib/Lower/Patterns.cc
	lib/Lower/Runtime.cc
	lib/Lower/Target.cc
	lib/Registration.cc
)
add_dependencies(idr_dialect idr_tablegen)
# Generated code is included as system headers so the project's warnings
# apply to our code, not to TableGen's output.
target_include_directories(idr_dialect SYSTEM PUBLIC
	${CMAKE_CURRENT_BINARY_DIR}/include
	${LLVM_INCLUDE_DIRS}
	${MLIR_INCLUDE_DIRS}
)
target_include_directories(idr_dialect PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_include_directories(idr_dialect PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/lib)
separate_arguments(IDR_LLVM_DEFINITIONS NATIVE_COMMAND ${LLVM_DEFINITIONS})
target_compile_definitions(idr_dialect PUBLIC ${IDR_LLVM_DEFINITIONS})
target_link_libraries(idr_dialect
	PUBLIC
		MLIRIR
		MLIRPass
		MLIRParser
		MLIRTransforms
		MLIRFuncDialect
		MLIRFuncTransforms
		MLIRArithDialect
		MLIRSCFDialect
		MLIRSCFTransforms
		MLIRUBDialect
		MLIRLLVMDialect
		MLIRMathDialect
		MLIRControlFlowDialect
		MLIRControlFlowInterfaces
		MLIRCallInterfaces
		MLIRInferIntRangeInterface
		MLIRSideEffectInterfaces
		MLIRSCFToControlFlow
		MLIRConvertToLLVMPass
		MLIRReconcileUnrealizedCasts
		MLIRTargetLLVMIRExport
		MLIRBuiltinToLLVMIRTranslation
		MLIRLLVMToLLVMIRTranslation
		${IDR_LLVM_CODEGEN_LIBS}
		# LOW-RT-1: the runtime, natively, for the folders and idr-eval's JIT,
		# with GMP, which it calls.
		idris_rt
		gmp
	PRIVATE
		idris_mlir_language_profile
)

add_executable(idris-mlir-opt tools/idris-mlir-opt.cc)
target_link_libraries(idris-mlir-opt PRIVATE
	idr_dialect
	MLIROptLib
	MLIRRegisterAllDialects
	MLIRRegisterAllExtensions
	MLIRRegisterAllPasses
	idris_mlir_language_profile
)

add_executable(idris-mlir-cc tools/idris-mlir-cc.cc)
target_link_libraries(idris-mlir-cc PRIVATE
	idr_dialect
	MLIRRegisterAllDialects
	MLIRRegisterAllExtensions
	MLIRRegisterAllPasses
	idris_mlir_language_profile
)
# TC-LINK-1: the runtime archive whose bitcode joins every program, checked
# (TC-RT-2) before idris-mlir-cc is built. --runtime overrides the path.
target_compile_definitions(idris-mlir-cc PRIVATE
	"IDRIS_MLIR_RUNTIME_ARCHIVE=\"${IDRIS_MLIR_RUNTIME_ARCHIVE}\""
)
add_dependencies(idris-mlir-cc idris_rt_check)

# docs/cutover.md 8.2: shrinking a module that makes a pass fail.
add_executable(idris-mlir-reduce tools/idris-mlir-reduce.cc)
target_link_libraries(idris-mlir-reduce PRIVATE
	idr_dialect
	MLIRReduceLib
	MLIRRegisterAllDialects
	MLIRRegisterAllExtensions
	MLIRRegisterAllPasses
	idris_mlir_language_profile
)

# The MLIR API is not module-aware: these targets never import std.
foreach(target idr_dialect idris-mlir-opt idris-mlir-cc idris-mlir-reduce)
	set_target_properties(${target} PROPERTIES
		CXX_MODULE_STD OFF
		CXX_SCAN_FOR_MODULES OFF
	)
endforeach()
