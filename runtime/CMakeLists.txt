# The runtime:
# C++ with no exceptions, no RTTI and no C++ library at link time, built into
# one archive of fat LTO objects. Their bitcode joins every program's LTO
# module in idris-mlir-cc; their native code links into
# idris-mlir-cc itself, where the folders and idr-eval's JIT call it.
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
# - fat LTO objects: bitcode for programs, native code for idris-mlir-cc;
# - no FP contraction.
add_library(idris_mlir_runtime_profile INTERFACE)
target_compile_options(idris_mlir_runtime_profile INTERFACE
	-O3
	${IDRIS_MLIR_RUNTIME_BASELINE}
	-flto=full
	-ffat-lto-objects
	-ffp-contract=off
	-ffunction-sections
	-fdata-sections
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

# Ryu's shortest digits, which double.cc wraps; C, unmodified.
add_library(idris_rt_ryu OBJECT "${IDRIS_MLIR_THIRD_PARTY}/ryu/ryu/d2s.c")
target_include_directories(idris_rt_ryu SYSTEM PRIVATE "${IDRIS_MLIR_THIRD_PARTY}/ryu")
target_link_libraries(idris_rt_ryu PRIVATE idris_mlir_runtime_profile)

add_library(idris_rt STATIC
	alloc.cc
	arrays.cc
	big.cc
	double.cc
	eval.cc
	gmp.cc
	io.cc
	numbers.cc
	platform_posix.cc
	${IDRIS_MLIR_RUNTIME_CPU_TEST}
	rc.cc
	start.cc
	strings.cc
	$<TARGET_OBJECTS:idris_rt_simdutf>
	$<TARGET_OBJECTS:idris_rt_ryu>
)
target_include_directories(idris_rt PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
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
	# C library calls _malloc_thread_cleanup, which musl does not, and
	# programs are single-threaded; its own small STL; and what the musl
	# sysroot provides.
	SNMALLOC_MIN_ALLOC_STEP_SIZE=8
	SNMALLOC_USE_THREAD_CLEANUP
	SNMALLOC_USE_SELF_VENDORED_STL
	SNMALLOC_PLATFORM_HAS_GETENTROPY
	SNMALLOC_HAS_LINUX_RANDOM_H
	SNMALLOC_HAS_LINUX_FUTEX_H
	SNMALLOC_USE_WAIT_ON_ADDRESS=1
)
target_link_libraries(idris_rt PRIVATE idris_mlir_runtime_profile idris_mlir_warnings)

foreach(target idris_rt_simdutf idris_rt_ryu idris_rt)
	set_target_properties(${target} PROPERTIES
		CXX_MODULE_STD OFF
		CXX_SCAN_FOR_MODULES OFF
	)
endforeach()
set_target_properties(idris_rt_simdutf PROPERTIES CXX_CLANG_TIDY "")
set_target_properties(idris_rt_ryu PROPERTIES C_CLANG_TIDY "")
set_target_properties(idris_rt PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")

# idris-mlir-cc reads the runtime's bitcode from here.
set(IDRIS_MLIR_RUNTIME_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/libidris_rt.a" PARENT_SCOPE)

# The link check. Every member of the archive is linked into one
# static-PIE executable with no C++ library and no unwinder, so a reference
# to the C++ runtime is an undefined symbol and fails the link. The archive
# check then refuses weak references to it, which a link accepts, and static
# constructors, which idris-mlir-cc refuses.
add_executable(idris_rt_link_check link_check.c)
target_link_libraries(idris_rt_link_check PRIVATE "$<LINK_LIBRARY:WHOLE_ARCHIVE,idris_rt>" gmp)
target_link_options(idris_rt_link_check PRIVATE -static-pie --unwindlib=none)

add_custom_command(
	OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/idris_rt.checked"
	COMMAND sh "${CMAKE_CURRENT_SOURCE_DIR}/check-archive.sh"
		"${CMAKE_NM}" "${CMAKE_READELF}" "$<TARGET_FILE:idris_rt>"
		"${CMAKE_CURRENT_BINARY_DIR}/idris_rt.checked"
	DEPENDS idris_rt idris_rt_link_check "${CMAKE_CURRENT_SOURCE_DIR}/check-archive.sh"
	COMMENT "Checking the runtime for C++ runtime references and static constructors"
	VERBATIM
)
add_custom_target(idris_rt_check ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/idris_rt.checked")
