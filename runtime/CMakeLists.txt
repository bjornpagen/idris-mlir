# The runtime:
# C++ with no exceptions, no RTTI and no C++ library at link time, built into
# one archive of objects that carry their bitcode as the target entry says
# (fat LTO objects on ELF). idris-mlir-cc prepares their bitcode once
# (--prepare-runtime, foreign/idr/CMakeLists.txt) into the object every
# executable links, whose bitcode joins every program's module for inlining;
# their native code links into idris-mlir-cc itself, where the folders and
# idr-eval's JIT call it.
# It includes the vendored libraries' headers, so like foreign/idr it is
# quarantine code.
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

# The runtime's profile, in every configuration:
# - optimized, since optnone bitcode would stay unoptimized in programs;
# - the target's baseline (its entry in CMakeLists.txt): idris-mlir-cc
#   raises every runtime function to the program's CPU;
# - bitcode with the native code, as the target's entry carries it: bitcode
#   for programs, native code for idris-mlir-cc;
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

# simdutf builds without the C++ library, with the
# encodings the runtime uses: UTF-8, UTF-32 and ASCII.
set(IDRIS_MLIR_SIMDUTF_DEFINITIONS
	SIMDUTF_NO_LIBCXX=1
	SIMDUTF_FEATURE_UTF16=0
	SIMDUTF_FEATURE_LATIN1=0
	SIMDUTF_FEATURE_BASE64=0
	SIMDUTF_FEATURE_DETECT_ENCODING=0
)

# Vendored code: compiled as upstream writes it, outside our warning set and
# the lint graph.
add_library(idris_rt_simdutf OBJECT "${IDRIS_MLIR_THIRD_PARTY}/simdutf/src/simdutf.cpp")
target_include_directories(idris_rt_simdutf SYSTEM PRIVATE
	"${IDRIS_MLIR_THIRD_PARTY}/simdutf/include"
	"${IDRIS_MLIR_THIRD_PARTY}/simdutf/src"
)
target_compile_definitions(idris_rt_simdutf PRIVATE ${IDRIS_MLIR_SIMDUTF_DEFINITIONS})
target_link_libraries(idris_rt_simdutf PRIVATE idris_mlir_runtime_profile)

# Ryu's shortest digits, which rt.doubles wraps; C, unmodified.
add_library(idris_rt_ryu OBJECT "${IDRIS_MLIR_THIRD_PARTY}/ryu/ryu/d2s.c")
target_include_directories(idris_rt_ryu SYSTEM PRIVATE "${IDRIS_MLIR_THIRD_PARTY}/ryu")
target_link_libraries(idris_rt_ryu PRIVATE idris_mlir_runtime_profile)

add_library(idris_rt STATIC
	$<TARGET_OBJECTS:idris_rt_simdutf>
	$<TARGET_OBJECTS:idris_rt_ryu>
)
# The runtime's modules, each a private file set of the one archive: its
# memory (rt.alloc), counting (rt.rc), strings (rt.strings), `cast` from
# String (rt.numerals), bigs (rt.big), doubles (rt.doubles), standard
# output and input (rt.io), compile-time evaluation's child (rt.eval) and
# the program's entry (rt.start).
target_sources(idris_rt
	PRIVATE
		FILE_SET rt_alloc TYPE CXX_MODULES FILES
			Alloc/Alloc.cppm
			Alloc/Arrays.cppm
			Alloc/Blocks.cppm
			Alloc/Cells.cppm
			Alloc/Classes.cppm
			Alloc/Gmp.cppm
	PRIVATE
		FILE_SET rt_rc TYPE CXX_MODULES FILES
			Rc/Rc.cppm
			Rc/Counting.cppm
			Rc/Freeing.cppm
			Rc/Objects.cppm
	PRIVATE
		FILE_SET rt_strings TYPE CXX_MODULES FILES
			Strings/Strings.cppm
			Strings/Concat.cppm
			Strings/Integers.cppm
			Strings/Making.cppm
			Strings/Order.cppm
			Strings/Replacement.cppm
			Strings/Scalars.cppm
			Strings/Show.cppm
			Strings/Simd.cppm
			Strings/Utf8.cppm
	PRIVATE
		FILE_SET rt_numerals TYPE CXX_MODULES FILES
			Numerals/Numerals.cppm
			Numerals/Machine.cppm
			Numerals/Reading.cppm
	PRIVATE
		FILE_SET rt_big TYPE CXX_MODULES FILES
			Big/Big.cppm
			Big/Arithmetic.cppm
			Big/Bitwise.cppm
			Big/Compare.cppm
			Big/Conversions.cppm
			Big/Digits.cppm
			Big/Operands.cppm
			Big/Words.cppm
	PRIVATE
		FILE_SET rt_doubles TYPE CXX_MODULES FILES
			Doubles/Doubles.cppm
			Doubles/Ieee.cppm
			Doubles/Parsing.cppm
			Doubles/Printing.cppm
			Doubles/Truncation.cppm
	PRIVATE
		FILE_SET rt_io TYPE CXX_MODULES FILES
			Io/Io.cppm
			Io/Bytes.cppm
			Io/Ending.cppm
			Io/Input.cppm
			Io/Output.cppm
			Io/Processors.cppm
			Io/Writing.cppm
	PRIVATE
		FILE_SET rt_eval TYPE CXX_MODULES FILES
			Eval/Eval.cppm
			Eval/Child.cppm
	PRIVATE
		FILE_SET rt_start TYPE CXX_MODULES FILES
			Start/Start.cppm
			Start/Entry.cppm
			Start/Runner.cppm
)
# rt.platform: the platform layer, a module, implemented on every POSIX
# system by Platform/Posix's partitions and on the target's processor by
# the target entry's partition.
target_sources(idris_rt
	PRIVATE
		FILE_SET rt_platform TYPE CXX_MODULES FILES
			Platform/Platform.cppm
			Platform/CpuBits.cppm
			Platform/Posix/Faults.cppm
			Platform/Posix/Memory.cppm
			Platform/Posix/Processors.cppm
			Platform/Posix/Stacks.cppm
			${IDRIS_MLIR_RUNTIME_CPU_TEST}
)
target_include_directories(idris_rt PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
# The target entry's list of the processor features programs may be compiled
# to use (cpu_features.h), which idr-lower and idris-mlir-cc read too.
target_compile_definitions(idris_rt PUBLIC
	"IDRIS_RT_CPU_FEATURES_FILE=\"${IDRIS_MLIR_RUNTIME_CPU_FEATURES}\""
)
target_include_directories(idris_rt SYSTEM PRIVATE
	"${IDRIS_MLIR_THIRD_PARTY}/snmalloc/src"
	"${IDRIS_MLIR_THIRD_PARTY}/simdutf/include"
	"${IDRIS_MLIR_THIRD_PARTY}/fast_float/include"
	"${IDRIS_MLIR_THIRD_PARTY}/ryu"
)
target_compile_definitions(idris_rt PRIVATE
	${IDRIS_MLIR_SIMDUTF_DEFINITIONS}
	# snmalloc: size classes that step by 8 bytes;
	# no thread teardown of its own, since both of the others need a static
	# destructor (pthread keys register one with [[gnu::destructor]]) or the
	# C++ runtime: a thread's cached memory is returned only if the
	# C library calls _malloc_thread_cleanup, which neither musl nor
	# libSystem does, and programs are single-threaded; its own small STL;
	# getentropy and waiting on an address, which every system of the target
	# entries has (Apple's platform draws entropy from CommonCrypto and waits
	# with __ulock_wait below a macOS 14.4 deployment target, both in
	# libSystem); the target entry's page, which its POSIX platforms take
	# from SNMALLOC_PAGESIZE (Apple's has the same number as a constant, and
	# rt.alloc:classes checks both); and what the entry says of the system.
	# snmalloc maps no executable memory, so nothing of MAP_JIT concerns it.
	SNMALLOC_MIN_ALLOC_STEP_SIZE=8
	SNMALLOC_USE_THREAD_CLEANUP
	SNMALLOC_USE_SELF_VENDORED_STL
	SNMALLOC_PLATFORM_HAS_GETENTROPY
	SNMALLOC_USE_WAIT_ON_ADDRESS=1
	SNMALLOC_PAGESIZE=${IDRIS_MLIR_PAGE_SIZE}
	${IDRIS_MLIR_RUNTIME_DEFINITIONS}
	# The bits of a stack address (rt.rc).
	IDRIS_RT_STACK_ADDRESS_BITS=${IDRIS_MLIR_STACK_ADDRESS_BITS}
	# The target's page size, which the runtime's startup check compares
	# with the system's (rt.platform:memory). The target entry's one number.
	IDRIS_RT_PAGE_SIZE=${IDRIS_MLIR_PAGE_SIZE}
)
# The same number for the tests, which build parts of the runtime for
# another page size and must not assume this one (tests/toolchain).
file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/page-size" CONTENT "${IDRIS_MLIR_PAGE_SIZE}\n")
# The library calls code generation makes for the target, as C names (the
# entry's symbol prefix is a separate fact): the copy and fill functions
# every target calls, then the target entry's JIT_LIBRARY_CALLS (what
# LLVM's code for the target calls beyond them, which idr-eval's JIT binds
# too). The e2e tests read it (tests/lib/heap.sh) to allow a program's
# object exactly the calls its code generation makes, so the list lives in
# the target entry and nowhere else.
set(IDRIS_MLIR_CODEGEN_SYMBOLS "")
foreach(codegen_call memcpy memset memmove ${IDRIS_MLIR_JIT_LIBRARY_CALLS})
	string(APPEND IDRIS_MLIR_CODEGEN_SYMBOLS "${codegen_call}\n")
endforeach()
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/codegen-symbols" "${IDRIS_MLIR_CODEGEN_SYMBOLS}")
# The prefix the object format puts before a C name ("_" on Mach-O), which
# a test takes off a symbol the linker tool prints (tests/lib/heap.sh).
file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/symbol-prefix"
	CONTENT "${IDRIS_MLIR_SYMBOL_PREFIX}\n")
# The function that fills in the processor's features before the test reads
# them, where no static constructor does.
if(IDRIS_MLIR_RUNTIME_CPU_INIT)
	target_compile_definitions(idris_rt PRIVATE "IDRIS_RT_CPU_FEATURES_INIT=${IDRIS_MLIR_RUNTIME_CPU_INIT}")
endif()
target_link_libraries(idris_rt PRIVATE idris_mlir_runtime_profile idris_mlir_warnings)

# No target imports std, which links the C++ library; the runtime scans
# for its own modules, the vendored code has none.
foreach(target idris_rt_simdutf idris_rt_ryu idris_rt)
	set_target_properties(${target} PROPERTIES CXX_MODULE_STD OFF)
endforeach()
set_target_properties(idris_rt_simdutf idris_rt_ryu PROPERTIES CXX_SCAN_FOR_MODULES OFF)
set_target_properties(idris_rt PROPERTIES CXX_SCAN_FOR_MODULES ON)
set_target_properties(idris_rt_simdutf PROPERTIES CXX_CLANG_TIDY "")
set_target_properties(idris_rt_ryu PROPERTIES C_CLANG_TIDY "")
set_target_properties(idris_rt PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")

# idris-mlir-cc reads the runtime's bitcode from here.
set(IDRIS_MLIR_RUNTIME_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/libidris_rt.a" PARENT_SCOPE)

# The link check. Every member of the archive is linked into one
# executable of the target with no C++ library and no unwinder, so a
# reference to the C++ runtime is an undefined symbol and fails the link.
# The archive check then refuses weak references to it, which a link
# accepts, and static constructors, which idris-mlir-cc refuses.
add_executable(idris_rt_link_check link_check.c)
target_link_libraries(idris_rt_link_check PRIVATE "$<LINK_LIBRARY:WHOLE_ARCHIVE,idris_rt>" ${IDRIS_MLIR_GMP})
target_link_options(idris_rt_link_check PRIVATE ${IDRIS_MLIR_EXECUTABLE_FLAGS} ${IDRIS_MLIR_NO_UNWINDER})

# The archive check with the target entry's spellings of the object format:
# check-archive ARCHIVE [STAMP] (tests/toolchain/runtime-archive-check runs
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
