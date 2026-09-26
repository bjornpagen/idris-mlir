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
mlir_tablegen(include/idr/IdrDialect.cpp.inc -gen-dialect-defs -dialect=idr)
mlir_tablegen(include/idr/IdrTypes.h.inc -gen-typedef-decls -typedefs-dialect=idr)
mlir_tablegen(include/idr/IdrTypes.cpp.inc -gen-typedef-defs -typedefs-dialect=idr)
mlir_tablegen(include/idr/IdrOps.h.inc -gen-op-decls)
mlir_tablegen(include/idr/IdrOps.cpp.inc -gen-op-defs)
set(LLVM_TARGET_DEFINITIONS ${CMAKE_CURRENT_SOURCE_DIR}/include/idr/Passes.td)
mlir_tablegen(include/idr/Passes.h.inc -gen-pass-decls -name Idr)
add_public_tablegen_target(idr_tablegen)

add_library(idr_dialect STATIC
	lib/IdrDialect.cpp
	lib/CheckInput.cpp
	lib/TailLoops.cpp
	lib/Lower.cpp
	lib/Registration.cpp
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
		MLIRControlFlowDialect
	PRIVATE
		idris_mlir_language_profile
)

llvm_map_components_to_libnames(IDR_LLVM_CODEGEN_LIBS nativecodegen passes)

add_executable(idris-mlir-opt tools/idris-mlir-opt.cpp)
target_link_libraries(idris-mlir-opt PRIVATE
	idr_dialect
	MLIROptLib
	MLIRRegisterAllDialects
	MLIRRegisterAllExtensions
	MLIRRegisterAllPasses
	idris_mlir_language_profile
)

add_executable(idris-mlir-cc tools/idris-mlir-cc.cpp)
target_link_libraries(idris-mlir-cc PRIVATE
	idr_dialect
	MLIRRegisterAllDialects
	MLIRRegisterAllExtensions
	MLIRRegisterAllPasses
	MLIRTargetLLVMIRExport
	MLIRBuiltinToLLVMIRTranslation
	MLIRLLVMToLLVMIRTranslation
	${IDR_LLVM_CODEGEN_LIBS}
	idris_mlir_language_profile
)

# The MLIR API is not module-aware: these targets never import std.
foreach(target idr_dialect idris-mlir-opt idris-mlir-cc)
	set_target_properties(${target} PROPERTIES
		CXX_MODULE_STD OFF
		CXX_SCAN_FOR_MODULES OFF
	)
endforeach()
