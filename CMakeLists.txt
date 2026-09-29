cmake_minimum_required(VERSION 4.0)

# The configure gate (adopted from bjornpagen/cpp-starter). The accepted
# toolchain series live in toolchain.lock.json only.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/toolchain.lock.json" IDRIS_MLIR_LOCK)
string(JSON IDRIS_MLIR_NINJA_SERIES GET "${IDRIS_MLIR_LOCK}" ninja accept)
string(JSON IDRIS_MLIR_CMAKE_SERIES GET "${IDRIS_MLIR_LOCK}" cmake accept)
string(JSON IDRIS_MLIR_LLVM_SERIES GET "${IDRIS_MLIR_LOCK}" llvm accept)

if(NOT CMAKE_GENERATOR STREQUAL "Ninja")
	message(FATAL_ERROR "Ninja is the only supported generator (got ${CMAKE_GENERATOR})")
endif()

if(NOT CMAKE_MAKE_PROGRAM)
	find_program(CMAKE_MAKE_PROGRAM ninja REQUIRED)
endif()

execute_process(
	COMMAND "${CMAKE_MAKE_PROGRAM}" --version
	RESULT_VARIABLE IDRIS_MLIR_NINJA_STATUS
	OUTPUT_VARIABLE IDRIS_MLIR_NINJA_VERSION
	OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT IDRIS_MLIR_NINJA_STATUS EQUAL 0
		OR NOT IDRIS_MLIR_NINJA_VERSION MATCHES "^${IDRIS_MLIR_NINJA_SERIES}\\.")
	message(FATAL_ERROR "Ninja ${IDRIS_MLIR_NINJA_SERIES}.x is required (got ${IDRIS_MLIR_NINJA_VERSION})")
endif()

if(NOT CMAKE_VERSION MATCHES "^${IDRIS_MLIR_CMAKE_SERIES}\\.")
	message(FATAL_ERROR "CMake ${IDRIS_MLIR_CMAKE_SERIES}.x is required: the import-std experimental UUID below is specific to that series (got ${CMAKE_VERSION})")
endif()

# PIN(cmake-import-std-uuid): the 4.2-series value — see PINS.md
set(CMAKE_EXPERIMENTAL_CXX_IMPORT_STD "d0edc3af-4c50-42ea-a356-e2862fe7a444")

project(idris_mlir LANGUAGES C CXX)

# project() makes libc++'s std module an ordinary target of this build; the
# lint graph checks our code, not libc++'s.
if(TARGET __cmake_cxx26)
	set_target_properties(__cmake_cxx26 PROPERTIES CXX_CLANG_TIDY "")
endif()

# PIN(platform-gate-x86_64): cpp-starter's platforms plus Linux x86_64
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
	set(IDRIS_MLIR_LINUX TRUE)
	if(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|aarch64|arm64)$")
		message(FATAL_ERROR "the machine boundary is Linux x86_64/arm64 and Darwin arm64 (got Linux ${CMAKE_SYSTEM_PROCESSOR})")
	endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
	set(IDRIS_MLIR_LINUX FALSE)
	if(NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
		message(FATAL_ERROR "the machine boundary is Linux x86_64/arm64 and Darwin arm64 (got Darwin ${CMAKE_SYSTEM_PROCESSOR})")
	endif()
else()
	message(FATAL_ERROR "the machine boundary is Linux and Darwin (got ${CMAKE_SYSTEM_NAME})")
endif()

option(IDRIS_MLIR_RUNTIME_SANITIZERS
	"Use runtime ASan+UBSan instead of trap-mode UBSan (the asan-ubsan preset)"
	OFF
)

if(IDRIS_MLIR_RUNTIME_SANITIZERS)
	# PIN(no-sanitizer-runtimes): static musl has no sanitizer runtimes — see PINS.md
	message(FATAL_ERROR "runtime sanitizers need compiler-rt's sanitizer runtimes, which the static musl toolchain does not have (PINS.md: no-sanitizer-runtimes)")
endif()

# The production compiler is the stage-2 clang of the pinned
# llvm-project, with libc++, for x86_64-unknown-linux-musl (tools/bootstrap.sh).
# PIN(clang-libcxx) — see PINS.md
foreach(lang C CXX)
	if(NOT CMAKE_${lang}_COMPILER_ID STREQUAL "Clang")
		message(FATAL_ERROR "production builds require the pinned clang (got ${CMAKE_${lang}_COMPILER_ID} for ${lang}); build it with tools/bootstrap.sh stage2")
	endif()
	if(NOT CMAKE_${lang}_COMPILER_VERSION MATCHES "^${IDRIS_MLIR_LLVM_SERIES}\\.")
		message(FATAL_ERROR "production builds require clang ${IDRIS_MLIR_LLVM_SERIES}.x (got ${CMAKE_${lang}_COMPILER_VERSION} for ${lang})")
	endif()
endforeach()
if(IDRIS_MLIR_LINUX AND NOT CMAKE_CXX_COMPILER_TARGET MATCHES "-linux-musl$")
	message(FATAL_ERROR "Linux builds target musl through the pinned sysroot; configure with a preset (got target '${CMAKE_CXX_COMPILER_TARGET}')")
endif()

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_MODULE_STD ON)

# Module-ABI flags must be global: CMake's synthesized import-std targets see
# only CMAKE_CXX_FLAGS, and the std module BMI must match every importer.
# PIN(clang-no-reflection): no -freflection — see PINS.md
string(APPEND CMAKE_CXX_FLAGS " -fno-exceptions -fno-rtti -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE")

include(CheckCXXSourceCompiles)
check_cxx_source_compiles([=[
#include <version>
#ifndef _LIBCPP_VERSION
#error the C++ library is not libc++
#endif
int main() { return 0; }
]=] IDRIS_MLIR_HAS_LIBCXX)
if(NOT IDRIS_MLIR_HAS_LIBCXX)
	message(FATAL_ERROR "production builds require libc++ from the pinned sysroot")
endif()

# Warnings are errors, for every target with our own C++ (the runtime too).
# PIN(clang-libcxx): the GCC-only diagnostics of cpp-starter's profile have
# no clang spelling and are left out — see PINS.md
add_library(idris_mlir_warnings INTERFACE)
target_compile_options(idris_mlir_warnings INTERFACE
	-Werror
	-Wall
	-Wextra
	-Wpedantic
	-Wconversion
	-Wsign-conversion
	-Wshadow
	-Wold-style-cast
	-Wcast-align
	-Wnull-dereference
	-Wdouble-promotion
	-Wformat
	-Wformat=2
	-Werror=format-security
	-Wimplicit-fallthrough
)

# The language profile of our tools. No FP contraction anywhere. The Release
# build is one LTO domain with LLVM and
# MLIR, whose libraries carry bitcode next to native code (fat LTO objects).
# PIN(stage2-thinlto): our code is full LTO, LLVM's own bitcode ThinLTO — see
# PINS.md
add_library(idris_mlir_language_profile INTERFACE)
target_link_libraries(idris_mlir_language_profile INTERFACE idris_mlir_warnings)

target_compile_options(idris_mlir_language_profile INTERFACE
	-fsanitize=undefined
	-fsanitize-trap=all
	-ftrivial-auto-var-init=zero
	-fstack-protector-strong
	-fzero-call-used-regs=used-gpr
	-fstack-clash-protection
	-fno-delete-null-pointer-checks
	-fno-strict-aliasing
	-fstrict-flex-arrays=3
	-ffp-contract=off
	"$<$<CONFIG:Release>:-ffunction-sections;-fdata-sections;-flto=full>"
)
target_link_options(idris_mlir_language_profile INTERFACE
	-fsanitize=undefined
	-fsanitize-trap=all
	"$<$<CONFIG:Release>:-flto=full;-Wl,--fat-lto-objects;-Wl,--thinlto-cache-dir=${CMAKE_BINARY_DIR}/lto.cache;-Wl,--thinlto-cache-policy=cache_size_bytes=2g>"
	"$<$<AND:$<CONFIG:Release>,$<BOOL:${IDRIS_MLIR_LINUX}>>:LINKER:--gc-sections>"
)

# PIN(darwin-inert-mitigations): FORTIFY is inert on musl and Darwin, and branch
# protection is Linux-only — see PINS.md
if(IDRIS_MLIR_LINUX)
	# PIN(platform-gate-x86_64): x86_64 uses CET where arm64 uses PAC/BTI
	target_compile_options(idris_mlir_language_profile INTERFACE
		-fPIE
		"$<IF:$<STREQUAL:${CMAKE_SYSTEM_PROCESSOR},x86_64>,-fcf-protection=full,-mbranch-protection=standard>"
	)
	# Static-PIE on musl. PIN(musl-thread-stacks): LLVM takes the
	# libc's default thread stack, which musl reads from PT_GNU_STACK — see
	# PINS.md
	target_link_options(idris_mlir_language_profile INTERFACE
		-static-pie
		LINKER:-z,relro
		LINKER:-z,now
		LINKER:-z,noexecstack
		LINKER:-z,nodlopen
		LINKER:-z,stack-size=8388608
	)
endif()

# The runtime, then the quarantine code that faces MLIR, which records where
# the runtime's archive is.
# PIN(zones-on-demand): cpp-starter's src/ and unsafe/ have no code, so
# they do not exist.
add_subdirectory(runtime)
add_subdirectory(foreign/idr)
