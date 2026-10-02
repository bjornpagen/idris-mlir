# The idr dialect, its passes and tools. Everything here faces the
# MLIR C++ API, so it is quarantine code: headers, TableGen, inheritance.
# PIN(mlir-cxx-api) — see PINS.md
# PIN(cmake-module-restat) — see PINS.md

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
# BitReader, Object), internalizes it (IPO) and writes the runtime it
# prepared (BitWriter); idr-eval compiles with ORC's LLJIT (OrcJIT) and the
# same pipeline (Passes). The runtime's bitcode carries inline assembly (CPU
# feature probes), which the object emitter parses with the native target's
# assembly parser.
llvm_map_components_to_libnames(IDR_LLVM_CODEGEN_LIBS nativecodegen ${LLVM_NATIVE_ARCH} passes linker bitreader bitwriter object ipo orcjit)

# idr.mlir is the one unit that parses MLIR's, LLVM's and TableGen's
# headers; every module imports their names from it. Each area of lib/
# lists its own sources, module units and plain ones.
add_library(idr_dialect STATIC lib/Registration.cc)
target_sources(idr_dialect PRIVATE
	FILE_SET idr_mlir TYPE CXX_MODULES FILES lib/Mlir.cppm
)
foreach(area
		Canonicalize
		Dialect
		Eval
		Expect
		Facts
		Fold
		Inline
		Lower
		Ownership
		Passes
		Specialize
		Stack
		Support
	)
	add_subdirectory(lib/${area})
endforeach()
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
# The target entry's triple and default CPU (CMakeLists.txt), which
# idr-target writes on every module and idris-mlir-cc prints. Programs are
# compiled for the triple the runtime is built for.
if(NOT CMAKE_CXX_COMPILER_TARGET)
	message(FATAL_ERROR "CMAKE_CXX_COMPILER_TARGET names the target programs are compiled for; use a preset")
endif()
target_compile_definitions(idr_dialect PUBLIC
	"IDRIS_MLIR_TARGET_TRIPLE=\"${CMAKE_CXX_COMPILER_TARGET}\""
	"IDRIS_MLIR_TARGET_CPU=\"${IDRIS_MLIR_TARGET_CPU}\""
)
# PIN(llvm-force-enable-stats): every translation unit, the tools' too,
# starts with this header, so that a pass statistic has the layout the MLIR
# library gives it in every build type.
target_compile_options(idr_dialect PUBLIC
	"SHELL:-include ${CMAKE_CURRENT_SOURCE_DIR}/lib/Support/EnableStatistics.h"
)
target_link_libraries(idr_dialect
	PUBLIC
		MLIRAnalysis
		MLIRIR
		MLIRPass
		MLIRParser
		MLIRBytecodeReader
		MLIRBytecodeWriter
		MLIRTransforms
		MLIRFuncDialect
		MLIRFuncTransforms
		MLIRArithDialect
		MLIRSCFDialect
		MLIRSCFTransforms
		MLIRMemRefDialect
		MLIRMemRefTransforms
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
		MLIRTargetLLVMIRTransforms
		MLIRBuiltinToLLVMIRTranslation
		MLIRLLVMToLLVMIRTranslation
		${IDR_LLVM_CODEGEN_LIBS}
		# The runtime, natively, for the folders and idr-eval's JIT,
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
# MLIRDebug: the action handlers (debug counters, action logging);
# MLIRRemarkStreamer: --remarks-file.
target_link_libraries(idris-mlir-cc PRIVATE
	idr_dialect
	MLIRDebug
	MLIRRegisterAllDialects
	MLIRRegisterAllExtensions
	MLIRRegisterAllPasses
	MLIRRemarkStreamer
	idris_mlir_language_profile
)
# The runtime every program links: the archive, checked before idris-mlir-cc
# is built, then optimized once by idris-mlir-cc itself (--prepare-runtime)
# into bitcode, which is the runtime the driver links by default (--runtime
# overrides the path, with the archive itself if need be).
set(IDRIS_MLIR_RUNTIME_BITCODE "${CMAKE_CURRENT_BINARY_DIR}/idris_rt.bc")
target_compile_definitions(idris-mlir-cc PRIVATE
	"IDRIS_MLIR_RUNTIME=\"${IDRIS_MLIR_RUNTIME_BITCODE}\""
)
add_dependencies(idris-mlir-cc idris_rt_check)
add_custom_command(
	OUTPUT "${IDRIS_MLIR_RUNTIME_BITCODE}"
	COMMAND idris-mlir-cc --prepare-runtime "--runtime=${IDRIS_MLIR_RUNTIME_ARCHIVE}"
		-o "${IDRIS_MLIR_RUNTIME_BITCODE}"
	DEPENDS idris-mlir-cc idris_rt idris_rt_check
	COMMENT "Optimizing the runtime once, for every program"
	VERBATIM
)
add_custom_target(idris_rt_prepared ALL DEPENDS "${IDRIS_MLIR_RUNTIME_BITCODE}")

# Shrinking a module that makes a pass fail.
add_executable(idris-mlir-reduce tools/idris-mlir-reduce.cc)
target_link_libraries(idris-mlir-reduce PRIVATE
	idr_dialect
	MLIRReduceLib
	MLIRRegisterAllDialects
	MLIRRegisterAllExtensions
	MLIRRegisterAllPasses
	idris_mlir_language_profile
)

# The MLIR API is not module-aware, so no target imports std: idr.mlir
# wraps its headers instead. Only idr_dialect has module units; the tools
# are plain translation units.
set_target_properties(idr_dialect idris-mlir-opt idris-mlir-cc idris-mlir-reduce PROPERTIES
	CXX_MODULE_STD OFF
)
set_target_properties(idr_dialect PROPERTIES CXX_SCAN_FOR_MODULES ON)

# Every plain unit reaches idr/Idr.h, which parses most of MLIR's headers:
# 18 of a unit's 22 seconds. Precompiled once, a unit takes 4. Module units
# parse their headers in their global module fragment, where a
# precompiled header does not belong.
target_precompile_headers(idr_dialect PRIVATE include/idr/Idr.h)
file(GLOB_RECURSE IDR_MODULE_UNITS CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/lib/*.cppm)
set_source_files_properties(${IDR_MODULE_UNITS} PROPERTIES SKIP_PRECOMPILE_HEADERS ON)
set_target_properties(idris-mlir-opt idris-mlir-cc idris-mlir-reduce PROPERTIES
	CXX_SCAN_FOR_MODULES OFF
)
