# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The exhaustive boxes: one googletest program per family of the
# arithmetic a rewrite rests on, each over every input of a reduced domain:
# the range rules (ranges), the big ops' range hooks (hooks) and the word
# each big op narrows to (words); and the properties of the dialect's own
# structures over small programs:
# its constants, flow, sources and verifier (ir), and the analyses of call
# cycles, labels and identities (analyses).
# googletest and googlemock are the pinned llvm-project's
# (third-party/unittest), which LLVM's install does not export: compiled
# here from upstream's sources, outside our warnings. make test-unit runs
# the programs.
set(IDR_GTEST "${PROJECT_SOURCE_DIR}/.toolchain/llvm-project/third-party/unittest")
set(IDR_BOXES ranges hooks words ir analyses)
set(IDR_BOX_SOURCES_ranges Ranges.cpp)
set(IDR_BOX_SOURCES_hooks Hooks.cpp HooksCompare.cpp)
set(IDR_BOX_SOURCES_words Words.cpp)
set(IDR_BOX_SOURCES_ir Constants.cpp Flow.cpp Sources.cpp Verify.cpp)
set(IDR_BOX_SOURCES_analyses Cycles.cpp Labels.cpp Identities.cpp)
# What the boxes call: the rules (the dialect's range rules, hooks and
# folders, the narrowing's widths), the analyses, the parser and the pass
# manager a program box reads and verifies its program with, the dialects
# its programs hold, arith's folders, and the runtime, natively, as
# idris-mlir-opt links it.
set(IDR_BOX_LINKS IdrNarrow IdrAnalysis IdrIR idris_rt MLIRAnalysis MLIRParser MLIRPass
	MLIRFuncDialect MLIRMemRefDialect MLIRTensorDialect MLIRUBDialect MLIRArithDialect MLIRIR
	MLIRSupport LLVMSupport)

# The typecheck build compiles the units against googletest's headers and
# links nothing.
if(IDRIS_MLIR_TYPECHECK)
	set(IDR_BOX_UNITS Main.cpp)
	foreach(box IN LISTS IDR_BOXES)
		list(APPEND IDR_BOX_UNITS ${IDR_BOX_SOURCES_${box}})
	endforeach()
	add_mlir_library(IdrUnitTests
		${IDR_BOX_UNITS}

		EXCLUDE_FROM_LIBMLIR
		DISABLE_INSTALL

		DEPENDS
		IdrOpsIncGen
		IdrRuntimeAbiIncGen
		IdrPassesIncGen

		LINK_LIBS PUBLIC
		${IDR_BOX_LINKS}
	)
	target_include_directories(IdrUnitTests SYSTEM PRIVATE
		"${IDR_GTEST}/googletest/include" "${IDR_GTEST}/googlemock/include")
	target_compile_definitions(IdrUnitTests PRIVATE GTEST_HAS_RTTI=0)
	return()
endif()

add_mlir_library(IdrGTest
	"${IDR_GTEST}/googletest/src/gtest-all.cc"
	"${IDR_GTEST}/googlemock/src/gmock-all.cc"

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL
	PARTIAL_SOURCES_INTENDED

	LINK_LIBS PUBLIC
	LLVMSupport
)
target_include_directories(IdrGTest SYSTEM PUBLIC
	"${IDR_GTEST}/googletest/include" "${IDR_GTEST}/googlemock/include")
target_include_directories(IdrGTest PRIVATE "${IDR_GTEST}/googletest" "${IDR_GTEST}/googlemock")
target_compile_definitions(IdrGTest PUBLIC GTEST_HAS_RTTI=0)
target_compile_options(IdrGTest PRIVATE -w)
set_target_properties(IdrGTest PROPERTIES CXX_CLANG_TIDY "")

foreach(box IN LISTS IDR_BOXES)
	add_executable(idr-box-${box} Main.cpp ${IDR_BOX_SOURCES_${box}})
	target_link_libraries(idr-box-${box} PRIVATE IdrGTest ${IDR_BOX_LINKS})
	add_dependencies(idr-box-${box} IdrOpsIncGen IdrRuntimeAbiIncGen IdrPassesIncGen)
endforeach()
