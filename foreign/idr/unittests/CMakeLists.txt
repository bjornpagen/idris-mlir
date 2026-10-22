# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The exhaustive boxes: one googletest program per family, each over every
# input of a reduced domain, or over cases drawn from seeds: the range rules
# and the interval instance of the inline meanings (ranges), the big ops'
# range hooks (hooks), the word each big op narrows to (words), the solver
# layer's components and the program graph (analyses), the shared
# vocabulary and the footprint (support), the structure ops' control flow
# (flow), the reuse token's handle (quantities), and a function's row held
# to its body between passes (rows). Every box runs as the tools do, on the
# runtime's runner under its own executable's name (Main.cpp), so each
# links the runtime and the support beside what its family reads, and each
# that links the dialect reads the dialect's precompiled header.
# googletest and googlemock are the pinned llvm-project's
# (third-party/unittest), which LLVM's install does not export: compiled
# here from upstream's sources, outside our warnings. make test-unit runs
# the programs.
set(IDR_GTEST "${PROJECT_SOURCE_DIR}/.toolchain/llvm-project/third-party/unittest")
set(IDR_BOXES ranges hooks words analyses support flow quantities rows)
set(IDR_BOX_SOURCES_ranges Ranges.cpp Intervals.cpp IntervalCases.cpp)
set(IDR_BOX_SOURCES_hooks Hooks.cpp HooksCompare.cpp)
set(IDR_BOX_SOURCES_words Words.cpp)
set(IDR_BOX_SOURCES_analyses Cycles.cpp Calls.cpp)
set(IDR_BOX_SOURCES_support Support.cpp Footprint.cpp)
set(IDR_BOX_SOURCES_flow Flow.cpp FlowCases.cpp)
set(IDR_BOX_SOURCES_quantities Quantities.cpp TokenCases.cpp)
set(IDR_BOX_SOURCES_rows Rows.cpp)
set(IDR_BOX_LINKS_ranges IdrIR MLIRInferIntRangeCommon)
set(IDR_BOX_LINKS_hooks IdrIR MLIRArithDialect)
set(IDR_BOX_LINKS_words IdrNarrow IdrIR MLIRArithDialect)
set(IDR_BOX_LINKS_analyses IdrSolver IdrIR MLIRPass)
set(IDR_BOX_LINKS_support "")
set(IDR_BOX_LINKS_flow IdrIR MLIRFuncDialect MLIRControlFlowInterfaces)
set(IDR_BOX_LINKS_quantities IdrIR MLIRParser)
set(IDR_BOX_LINKS_rows IdrIR MLIRPass)
set(IDR_BOX_RUNNER_LINKS IdrSupport idris_rt LLVMSupport)

# What the vocabulary refuses to compile (Refusals.cpp), in no box: one
# compile with clang's -verify, which passes only when every refusal it
# marks is made, at its line and with its message, and nothing else is.
# It reads the headers every library reads, upstream's and the generated
# ones as system headers as the build does, and none of our warnings, so
# that only the refusals speak. The build runs it as it builds the boxes.
set(IDR_REFUSALS_VERIFIED "${CMAKE_CURRENT_BINARY_DIR}/Refusals.verified")
set(IDR_REFUSALS_SYSTEM_INCLUDES ${LLVM_INCLUDE_DIRS} ${MLIR_INCLUDE_DIRS} "${CMAKE_CURRENT_BINARY_DIR}/../include")
list(TRANSFORM IDR_REFUSALS_SYSTEM_INCLUDES PREPEND "-isystem")
add_custom_command(
	OUTPUT "${IDR_REFUSALS_VERIFIED}"
	COMMAND "${CMAKE_CXX_COMPILER}" "--target=${CMAKE_CXX_COMPILER_TARGET}" ${CMAKE_CXX26_STANDARD_COMPILE_OPTION}
		-fno-rtti -fno-exceptions -fsyntax-only -ferror-limit=0
		-Xclang -verify -Xclang -verify-ignore-unexpected=note
		"-I${PROJECT_SOURCE_DIR}/foreign/idr/include"
		"$<LIST:TRANSFORM,$<TARGET_PROPERTY:idris_rt,INTERFACE_INCLUDE_DIRECTORIES>,PREPEND,-I>"
		${IDR_REFUSALS_SYSTEM_INCLUDES}
		${IDR_LLVM_DEFINITIONS}
		"$<LIST:TRANSFORM,$<TARGET_PROPERTY:idris_rt,INTERFACE_COMPILE_DEFINITIONS>,PREPEND,-D>"
		-MD -MT "${IDR_REFUSALS_VERIFIED}" -MF "${IDR_REFUSALS_VERIFIED}.d"
		"${CMAKE_CURRENT_SOURCE_DIR}/Refusals.cpp"
	COMMAND "${CMAKE_COMMAND}" -E touch "${IDR_REFUSALS_VERIFIED}"
	DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/Refusals.cpp" IdrOpsIncGen IdrPassesIncGen
	DEPFILE "${IDR_REFUSALS_VERIFIED}.d"
	COMMENT "Checking what the vocabulary refuses to compile"
	COMMAND_EXPAND_LISTS
	VERBATIM
)
add_custom_target(idr-refusals ALL DEPENDS "${IDR_REFUSALS_VERIFIED}")

# The typecheck build compiles the boxes' units against googletest's
# headers and links nothing; the refusals' unit is in none of them.
if(IDRIS_MLIR_TYPECHECK)
	set(IDR_BOX_UNITS Main.cpp)
	set(IDR_BOX_LINKS ${IDR_BOX_RUNNER_LINKS})
	foreach(box IN LISTS IDR_BOXES)
		list(APPEND IDR_BOX_UNITS ${IDR_BOX_SOURCES_${box}})
		list(APPEND IDR_BOX_LINKS ${IDR_BOX_LINKS_${box}})
	endforeach()
	list(REMOVE_DUPLICATES IDR_BOX_LINKS)
	set(LLVM_OPTIONAL_SOURCES Refusals.cpp)
	add_mlir_library(IdrUnitTests
		${IDR_BOX_UNITS}

		EXCLUDE_FROM_LIBMLIR
		DISABLE_INSTALL

		DEPENDS
		IdrOpsIncGen
		IdrPassesIncGen

		LINK_LIBS PUBLIC
		${IDR_BOX_LINKS}
	)
	target_include_directories(IdrUnitTests SYSTEM PRIVATE
		"${IDR_GTEST}/googletest/include" "${IDR_GTEST}/googlemock/include")
	target_compile_definitions(IdrUnitTests PRIVATE GTEST_HAS_RTTI=0 "IDR_TOOL_NAME=\"IdrUnitTests\"")
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
	target_link_libraries(idr-box-${box} PRIVATE IdrGTest ${IDR_BOX_LINKS_${box}} ${IDR_BOX_RUNNER_LINKS})
	target_compile_definitions(idr-box-${box} PRIVATE "IDR_TOOL_NAME=\"idr-box-${box}\"")
	add_dependencies(idr-box-${box} IdrOpsIncGen IdrPassesIncGen)
	if(IdrIR IN_LIST IDR_BOX_LINKS_${box})
		target_precompile_headers(idr-box-${box} REUSE_FROM IdrIR)
	endif()
endforeach()
