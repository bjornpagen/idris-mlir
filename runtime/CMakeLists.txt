# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The runtime:
# C++ with no exceptions, no RTTI and no C++ library at link time, built into
# one archive of objects that carry their bitcode as the target entry says
# (fat LTO objects on ELF). idris-mlir prepares their bitcode once
# (--prepare-runtime, foreign/idr/CMakeLists.txt) into the object every
# executable links, whose bitcode joins every program's module for inlining;
# their native code links into idris-mlir itself, where the folders call it.
# Every program links it with no C++ library, so it has its own profile,
# not the tools'.
# PIN(runtime-quarantine), PIN(runtime-cx16) — see PINS.md

set(IDRIS_MLIR_THIRD_PARTY "${PROJECT_SOURCE_DIR}/third_party")
foreach(file
		snmalloc/src/snmalloc/snmalloc.h
		simdutf/src/simdutf.cpp
		fast_float/include/fast_float/fast_float.h
		ryu/ryu/d2s.c)
	if(NOT EXISTS "${IDRIS_MLIR_THIRD_PARTY}/${file}")
		message(FATAL_ERROR "third_party/${file} is missing; run: git submodule update --init")
	endif()
endforeach()

# snmalloc as its own build describes it, header-only: its interface target
# carries what it finds of the system, and what is ours: the step of its
# size classes (a cell of a header and two fields, 24 bytes, is a size
# class of its own), the target entry's page, and its own small STL, since
# the runtime links no C++ library. Its thread teardown, which a
# header-only build leaves to its user, is idris_rt_compile's.
set(SNMALLOC_HEADER_ONLY_LIBRARY ON CACHE BOOL "" FORCE)
set(SNMALLOC_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(SNMALLOC_MIN_ALLOC_STEP_SIZE 8 CACHE STRING "" FORCE)
set(SNMALLOC_PAGESIZE ${IDRIS_MLIR_PAGE_SIZE} CACHE STRING "" FORCE)
set(SNMALLOC_USE_SELF_VENDORED_STL ON CACHE BOOL "" FORCE)
add_subdirectory("${IDRIS_MLIR_THIRD_PARTY}/snmalloc" "${CMAKE_CURRENT_BINARY_DIR}/snmalloc"
	EXCLUDE_FROM_ALL SYSTEM)

# The runtime's units, one directory per part, each with one header its
# units share: its memory (Alloc), counting (Rc), strings (Strings), `cast`
# from String (Numerals), bigs (Big), doubles (Doubles), input and output,
# the standard streams and base's files, directories, process, terminal,
# errors and clocks behind the handle table (Io), and the program's entry
# (Start). The platform layer (Platform) is implemented on every POSIX
# system by Platform/Posix and on the target's processor by the target
# entry's unit (IDRIS_MLIR_RUNTIME_CPU_TEST).
set(IDRIS_RT_SOURCES
	Alloc/Arrays.cpp
	Alloc/Cells.cpp
	Alloc/Gmp.cpp
	Rc/Counting.cpp
	Rc/Freeing.cpp
	Strings/Concat.cpp
	Strings/Making.cpp
	Strings/Order.cpp
	Strings/Replacement.cpp
	Strings/Scalars.cpp
	Strings/Show.cpp
	Strings/Simd.cpp
	Numerals/Machine.cpp
	Numerals/Reading.cpp
	Big/Arithmetic.cpp
	Big/Bitwise.cpp
	Big/Compare.cpp
	Big/Conversions.cpp
	Big/Digits.cpp
	Big/Operands.cpp
	Big/Words.cpp
	Doubles/Parsing.cpp
	Doubles/Printing.cpp
	Doubles/Truncation.cpp
	Io/Buffer.cpp
	Io/Bytes.cpp
	Io/Clock.cpp
	Io/Directories.cpp
	Io/Ending.cpp
	Io/Errors.cpp
	Io/Files.cpp
	Io/FileTimes.cpp
	Io/Handles.cpp
	Io/Input.cpp
	Io/Lines.cpp
	Io/Output.cpp
	Io/Process.cpp
	Io/Processors.cpp
	Io/Scratch.cpp
	Io/Terminal.cpp
	Start/Entry.cpp
	Start/Runner.cpp
	Platform/Posix/Clocks.cpp
	Platform/Posix/Directories.cpp
	Platform/Posix/Faults.cpp
	Platform/Posix/Files.cpp
	Platform/Posix/Memory.cpp
	Platform/Posix/Process.cpp
	Platform/Posix/Processors.cpp
	Platform/Posix/Stacks.cpp
	Platform/Posix/Terminal.cpp
	${IDRIS_MLIR_RUNTIME_CPU_TEST}
)

# What a unit that includes the runtime's headers reads: this directory
# (idris_rt.h, the C ABI; cpu_features.h; each part's header, by its path
# from here) and the target entry's list of the processor features programs
# may be compiled to use, which cpu_features.h includes and idr-lower and
# idris-mlir read too. idris_rt carries them, with SCOPE, to every library
# that links it.
set(IDRIS_RT_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}"
	# idris_rt_ops.h: the C declarations of the functions the dialect's ops
	# call, generated from their ODS (foreign/idr/include/idr/IR).
	"${PROJECT_BINARY_DIR}/foreign/idr/include/idr/IR")
function(idris_rt_headers scope)
	target_include_directories(idris_rt ${scope} ${IDRIS_RT_INCLUDE_DIRECTORIES})
	target_compile_definitions(idris_rt ${scope}
		"IDRIS_RT_CPU_FEATURES_FILE=\"${IDRIS_MLIR_RUNTIME_CPU_FEATURES}\""
	)
endfunction()

# The runtime's profile, in every configuration:
# - optimized, since optnone bitcode would stay unoptimized in programs;
# - the target's baseline (its entry in CMakeLists.txt): idris-mlir
#   raises every runtime function to the program's CPU;
# - bitcode with the native code, as the target's entry carries it: bitcode
#   for programs, native code for idris-mlir;
# - each function and datum in its own section, so the linker drops the
#   unused ones (the target entry's IDRIS_MLIR_RUNTIME_SECTIONS, which is
#   empty where the object's bitcode forbids them);
# - no FP contraction.
add_library(idris_mlir_runtime_profile INTERFACE)
target_compile_options(idris_mlir_runtime_profile INTERFACE
	-O3
	${IDRIS_MLIR_RUNTIME_BASELINE}
	${IDRIS_MLIR_RUNTIME_BITCODE_FLAGS}
	-ffp-contract=off
	${IDRIS_MLIR_RUNTIME_SECTIONS}
)
target_compile_definitions(idris_mlir_runtime_profile INTERFACE NDEBUG)

# simdutf builds without the C++ library, with the one encoding the
# runtime calls it for, UTF-8: every implementation's table of virtual
# functions names each kernel it has, so a kernel left in would join every
# program that reaches a string operation.
set(IDRIS_MLIR_SIMDUTF_DEFINITIONS
	SIMDUTF_NO_LIBCXX=1
	SIMDUTF_FEATURE_UTF16=0
	SIMDUTF_FEATURE_UTF32=0
	SIMDUTF_FEATURE_ASCII=0
	SIMDUTF_FEATURE_LATIN1=0
	SIMDUTF_FEATURE_BASE64=0
	SIMDUTF_FEATURE_DETECT_ENCODING=0
)

# How TARGET compiles the runtime's units: the profile, the warnings, the
# vendored libraries' headers and what they are told.
function(idris_rt_compile target)
	target_include_directories(${target} SYSTEM PRIVATE
		"${IDRIS_MLIR_THIRD_PARTY}/simdutf/include"
		"${IDRIS_MLIR_THIRD_PARTY}/fast_float/include"
		"${IDRIS_MLIR_THIRD_PARTY}/ryu"
	)
	target_compile_definitions(${target} PRIVATE
		${IDRIS_MLIR_SIMDUTF_DEFINITIONS}
		# snmalloc's thread teardown: none of its own, since the others need a
		# static destructor (pthread keys register one with [[gnu::destructor]])
		# or the C++ runtime. A thread's cached memory is returned only if the
		# C library calls _malloc_thread_cleanup, which neither glibc nor
		# libSystem does. Programs are single-threaded; in idris-mlir, whose
		# folders run on worker threads, a thread that ends keeps its cache, a
		# cost bounded by the threads a compilation starts.
		SNMALLOC_USE_THREAD_CLEANUP
		# The target's page size, which the runtime's startup check compares
		# with the system's (Platform/Posix/Memory.cpp). The target entry's one
		# number.
		IDRIS_RT_PAGE_SIZE=${IDRIS_MLIR_PAGE_SIZE}
		# The target's user address width (Platform/Address.h), the entry's.
		IDRIS_RT_USER_ADDRESS_BITS=${IDRIS_MLIR_USER_ADDRESS_BITS}
	)
	target_link_libraries(${target} PRIVATE snmalloc idris_mlir_runtime_profile idris_mlir_warnings)
endfunction()

# The typecheck build (IDRIS_MLIR_TYPECHECK, CMakeLists.txt) compiles the
# runtime's units with the host's compiler into objects that nothing links,
# so that it checks them as it checks foreign/idr; idris_rt is then their
# headers alone. GMP's header is the sysroot's when the bootstrap built GMP
# there, which the host's compiler does not search, or else the host's; it
# is copied alone, so that no other header of the sysroot enters the host's
# compile.
if(IDRIS_MLIR_TYPECHECK)
	add_library(idris_rt INTERFACE)
	idris_rt_headers(INTERFACE)
	find_file(IDRIS_MLIR_TYPECHECK_GMP_HEADER gmp.h
		HINTS "${PROJECT_SOURCE_DIR}/.toolchain/sysroot/usr/include"
		DOC "GMP's header, for the typecheck build's compile of the runtime")
	if(NOT IDRIS_MLIR_TYPECHECK_GMP_HEADER)
		message(FATAL_ERROR "the typecheck build compiles the runtime, which includes gmp.h: run tools/bootstrap.sh gmp, or set IDRIS_MLIR_TYPECHECK_GMP_HEADER to the host's gmp.h")
	endif()
	configure_file("${IDRIS_MLIR_TYPECHECK_GMP_HEADER}"
		"${CMAKE_CURRENT_BINARY_DIR}/typecheck-gmp/gmp.h" COPYONLY)
	add_library(idris_rt_typecheck OBJECT ${IDRIS_RT_SOURCES})
	target_link_libraries(idris_rt_typecheck PRIVATE idris_rt)
	idris_rt_compile(idris_rt_typecheck)
	target_include_directories(idris_rt_typecheck SYSTEM PRIVATE
		"${CMAKE_CURRENT_BINARY_DIR}/typecheck-gmp")
	add_dependencies(idris_rt_typecheck IdrRuntimeAbiIncGen)
	add_custom_target(idris_rt_check)
	add_dependencies(idris_rt_check idris_rt_typecheck)
	return()
endif()

# Vendored code: compiled as upstream writes it, outside our warning set and
# the lint graph.
add_library(idris_rt_simdutf OBJECT "${IDRIS_MLIR_THIRD_PARTY}/simdutf/src/simdutf.cpp")
target_include_directories(idris_rt_simdutf SYSTEM PRIVATE
	"${IDRIS_MLIR_THIRD_PARTY}/simdutf/include"
	"${IDRIS_MLIR_THIRD_PARTY}/simdutf/src"
)
target_compile_definitions(idris_rt_simdutf PRIVATE ${IDRIS_MLIR_SIMDUTF_DEFINITIONS})
target_link_libraries(idris_rt_simdutf PRIVATE idris_mlir_runtime_profile)

# Ryu's shortest digits, which Doubles/Printing.cpp wraps; C, unmodified.
add_library(idris_rt_ryu OBJECT "${IDRIS_MLIR_THIRD_PARTY}/ryu/ryu/d2s.c")
target_include_directories(idris_rt_ryu SYSTEM PRIVATE "${IDRIS_MLIR_THIRD_PARTY}/ryu")
target_link_libraries(idris_rt_ryu PRIVATE idris_mlir_runtime_profile)

add_library(idris_rt STATIC
	${IDRIS_RT_SOURCES}
	$<TARGET_OBJECTS:idris_rt_simdutf>
	$<TARGET_OBJECTS:idris_rt_ryu>
)
idris_rt_headers(PUBLIC)
idris_rt_compile(idris_rt)
add_dependencies(idris_rt IdrRuntimeAbiIncGen)
# Its bigs call GMP, so whatever links it links GMP.
target_link_libraries(idris_rt INTERFACE ${IDRIS_MLIR_GMP})
# The same number for the tests, which build parts of the runtime for
# another page size and must not assume this one (tests/page-size-mismatch).
file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/page-size" CONTENT "${IDRIS_MLIR_PAGE_SIZE}\n")
# What a C program that includes idris_rt.h is compiled with, one flag a
# line: the runtime's include directories, the generated one among them,
# from the one list above (the runtime's tests compile against the ABI).
list(TRANSFORM IDRIS_RT_INCLUDE_DIRECTORIES PREPEND "-I" OUTPUT_VARIABLE IDRIS_RT_C_FLAGS)
list(JOIN IDRIS_RT_C_FLAGS "\n" IDRIS_RT_C_FLAGS_TEXT)
file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/c-flags" CONTENT "${IDRIS_RT_C_FLAGS_TEXT}\n")
# The library calls code generation makes for the target, as C names (the
# entry's symbol prefix is a separate fact): the copy and fill functions
# every target calls, then the target entry's IDRIS_MLIR_CODEGEN_LIBRARY_CALLS
# (what LLVM's code for the target calls beyond them). The e2e tests read it
# (harness/lib/heap.sh) to allow a program's object exactly the calls its code
# generation makes, so the list lives in the target entry and nowhere else.
set(IDRIS_MLIR_CODEGEN_SYMBOLS "")
foreach(codegen_call memcpy memset memmove ${IDRIS_MLIR_CODEGEN_LIBRARY_CALLS})
	string(APPEND IDRIS_MLIR_CODEGEN_SYMBOLS "${codegen_call}\n")
endforeach()
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/codegen-symbols" "${IDRIS_MLIR_CODEGEN_SYMBOLS}")
# The prefix the object format puts before a C name ("_" on Mach-O), which
# a test takes off a symbol the linker tool prints (harness/lib/heap.sh).
file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/symbol-prefix"
	CONTENT "${IDRIS_MLIR_SYMBOL_PREFIX}\n")

set_target_properties(idris_rt_simdutf PROPERTIES CXX_CLANG_TIDY "")
set_target_properties(idris_rt_ryu PROPERTIES C_CLANG_TIDY "")
set_target_properties(idris_rt PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")

# idris-mlir reads the runtime's bitcode from here.
set(IDRIS_MLIR_RUNTIME_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/libidris_rt.a" PARENT_SCOPE)

# The link check. Every member of the archive is linked into one
# executable of the target with no C++ library and no unwinder, so a
# reference to the C++ runtime is an undefined symbol and fails the link.
# The archive check then refuses weak references to it, which a link
# accepts, and static constructors, which idris-mlir refuses.
add_executable(idris_rt_link_check link_check.c)
target_link_libraries(idris_rt_link_check PRIVATE "$<LINK_LIBRARY:WHOLE_ARCHIVE,idris_rt>" ${IDRIS_MLIR_GMP})
target_link_options(idris_rt_link_check PRIVATE ${IDRIS_MLIR_EXECUTABLE_FLAGS} ${IDRIS_MLIR_NO_UNWINDER})

# The archive check with the target entry's spellings of the object format:
# check-archive ARCHIVE [STAMP] (tests/runtime-archive-check runs
# it too).
set(IDRIS_MLIR_CHECK_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/check-archive")
list(JOIN IDRIS_MLIR_CONSTRUCTOR_SECTIONS " " IDRIS_MLIR_CONSTRUCTOR_SECTIONS_TEXT)
file(CONFIGURE OUTPUT "${IDRIS_MLIR_CHECK_ARCHIVE}" CONTENT [=[#!/bin/sh
# Generated by CMake from the target entry (CMakeLists.txt): the archive
# check with the target's symbol prefix and constructor sections.
exec sh '@CMAKE_CURRENT_SOURCE_DIR@/check-archive.sh' '@CMAKE_NM@' '@CMAKE_OBJDUMP@' \
  '@IDRIS_MLIR_SYMBOL_PREFIX@' '@IDRIS_MLIR_CONSTRUCTOR_SECTIONS_TEXT@' "$@"
]=] @ONLY)
add_custom_command(
	OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/idris_rt.checked"
	COMMAND sh "${IDRIS_MLIR_CHECK_ARCHIVE}" "$<TARGET_FILE:idris_rt>"
		"${CMAKE_CURRENT_BINARY_DIR}/idris_rt.checked"
	DEPENDS idris_rt idris_rt_link_check "${CMAKE_CURRENT_SOURCE_DIR}/check-archive.sh"
		"${IDRIS_MLIR_CHECK_ARCHIVE}"
	COMMENT "Checking the runtime for C++ runtime references and static constructors"
	VERBATIM
)
add_custom_target(idris_rt_check ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/idris_rt.checked")
