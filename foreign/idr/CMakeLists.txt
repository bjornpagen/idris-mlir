# The idr dialect, its passes and tools. Everything here faces the
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
# BitReader, Object) and internalizes it (IPO); idr-eval compiles
# with ORC's LLJIT (OrcJIT) and the same pipeline (Passes).
llvm_map_components_to_libnames(IDR_LLVM_CODEGEN_LIBS nativecodegen passes linker bitreader object ipo orcjit)

add_library(idr_dialect STATIC
	lib/Dialect/Canonicalize/Apply.cc
	lib/Dialect/Canonicalize/Calls.cc
	lib/Dialect/Canonicalize/CaseOfCase.cc
	lib/Dialect/Canonicalize/Matches.cc
	lib/Dialect/Canonicalize/Meet.cc
	lib/Dialect/Canonicalize/Merge.cc
	lib/Dialect/Canonicalize/Sink.cc
	lib/Dialect/Canonicalize/Strings.cc
	lib/Dialect/Dialect.cc
	lib/Dialect/Ops.cc
	lib/Facts/Effects.cc
	lib/Facts/Evaluate.cc
	lib/Facts/Functions.cc
	lib/Facts/Moves.cc
	lib/Facts/Values.cc
	lib/Eval/Child.cc
	lib/Eval/Eval.cc
	lib/Eval/Jit.cc
	lib/Eval/Reify.cc
	lib/Expect/Allocation.cc
	lib/Expect/Breakers.cc
	lib/Expect/Clones.cc
	lib/Expect/Closures.cc
	lib/Expect/Facts.cc
	lib/Expect/Pass.cc
	lib/Expect/Quantities.cc
	lib/Fold/Fold.cc
	lib/Inline/Inline.cc
	lib/Lower.cc
	lib/Lower/Counting.cc
	lib/Lower/Layout.cc
	lib/Lower/Matches.cc
	lib/Lower/Patterns.cc
	lib/Lower/Predecessors.cc
	lib/Lower/Runtime.cc
	lib/Lower/Target.cc
	lib/Ownership/Borrow.cc
	lib/Ownership/Counting.cc
	lib/Ownership/Counts.cc
	lib/Ownership/Ops.cc
	lib/Ownership/Rc.cc
	lib/Ownership/ResetReuse.cc
	lib/Ownership/Verify.cc
	lib/Registration.cc
	lib/Passes/CheckProfile.cc
	lib/Passes/Defunctionalize.cc
	lib/Passes/LoopBreakers.cc
	lib/Passes/Prune.cc
	lib/Passes/Simplify.cc
	lib/Passes/TailLoops.cc
	lib/Specialize/BindingTimes.cc
	lib/Specialize/Clones.cc
	lib/Specialize/Pass.cc
	lib/Specialize/Pattern.cc
	lib/Specialize/Quantity.cc
	lib/Specialize/Raise.cc
	lib/Specialize/Run.cc
	lib/Specialize/Specialize.cc
	lib/Stack/Cell.cc
	lib/Stack/Escape.cc
	lib/Stack/Pass.cc
	lib/Stack/Recursion.cc
	lib/Stack/Tail.cc
	lib/Canonicalize/Pass.cc
	lib/Support/PatternCounts.cc
	lib/Support/PipelineStatistics.cc
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
# The runtime archive whose bitcode joins every program, checked before
# idris-mlir-cc is built. --runtime overrides the path.
target_compile_definitions(idris-mlir-cc PRIVATE
	"IDRIS_MLIR_RUNTIME_ARCHIVE=\"${IDRIS_MLIR_RUNTIME_ARCHIVE}\""
)
add_dependencies(idris-mlir-cc idris_rt_check)

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

# The MLIR API is not module-aware: these targets never import std.
foreach(target idr_dialect idris-mlir-opt idris-mlir-cc idris-mlir-reduce)
	set_target_properties(${target} PROPERTIES
		CXX_MODULE_STD OFF
		CXX_SCAN_FOR_MODULES OFF
	)
endforeach()
