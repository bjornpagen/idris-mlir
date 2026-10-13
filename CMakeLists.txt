cmake_minimum_required(VERSION 4.0)

# The configure gate. The accepted toolchain series live in
# toolchain.lock.json only.
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
	message(FATAL_ERROR "CMake ${IDRIS_MLIR_CMAKE_SERIES}.x is required (got ${CMAKE_VERSION})")
endif()

# ccache, when the machine has one (on PATH, or MacPorts'), launches every
# C and C++ compile, on the cache tools/bootstrap.sh configures
# (.toolchain/ccache): a rebuild recompiles only what changed, in every
# preset, as in the toolchain's builds. CMake copies it onto each target
# created after it. No target uses a precompiled header, which ccache
# cannot cache. The launcher changes nothing a compile produces.
find_program(IDRIS_MLIR_CCACHE ccache HINTS /opt/local/bin)
if(IDRIS_MLIR_CCACHE)
	set(IDRIS_MLIR_CCACHE_LAUNCHER "${CMAKE_COMMAND}" -E env
		"CCACHE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.toolchain/ccache" "${IDRIS_MLIR_CCACHE}")
	set(CMAKE_C_COMPILER_LAUNCHER ${IDRIS_MLIR_CCACHE_LAUNCHER})
	set(CMAKE_CXX_COMPILER_LAUNCHER ${IDRIS_MLIR_CCACHE_LAUNCHER})
endif()

project(idris_mlir LANGUAGES C CXX)

# The typecheck build (make typecheck, the typecheck preset, whose
# toolchain file tools/bootstrap.sh typecheck writes): every unit of
# foreign/idr compiled by the host's clang against the TableGen-only LLVM
# and MLIR, nothing linked but idris-mlir-tblgen, and the runtime's units
# compiled into objects nothing links. It checks that the code compiles
# where stage 2 is not built; it is no build of the compiler. The typecheck
# toolchain file sets it, so it is declared after project() has read that
# file.
option(IDRIS_MLIR_TYPECHECK "Compile foreign/idr with the host's clang against the TableGen-only LLVM/MLIR, and link nothing but idris-mlir-tblgen" OFF)

# PIN(platform-gate-x86_64): the build runs on the two machines whose
# targets the compiler has, Linux x86_64 and Darwin arm64, the same
# machines tools/bootstrap.sh builds a toolchain on.
if(NOT (CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
		AND NOT (CMAKE_SYSTEM_NAME STREQUAL "Darwin" AND CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64"))
	message(FATAL_ERROR "the machine boundary is Linux x86_64 and Darwin arm64 (got ${CMAKE_SYSTEM_NAME} ${CMAKE_SYSTEM_PROCESSOR})")
endif()

# The production compiler is the stage-2 clang of the pinned
# llvm-project, with the pinned libc++, for the target its toolchain file
# names (tools/bootstrap.sh writes it; every preset reads it).
# PIN(clang-libcxx) — see PINS.md
# The typecheck build's compiler is the host's, by design.
if(NOT IDRIS_MLIR_TYPECHECK)
	foreach(lang C CXX)
		if(NOT CMAKE_${lang}_COMPILER_ID STREQUAL "Clang")
			message(FATAL_ERROR "production builds require the pinned clang (got ${CMAKE_${lang}_COMPILER_ID} for ${lang}); build it with tools/bootstrap.sh stage2")
		endif()
		if(NOT CMAKE_${lang}_COMPILER_VERSION MATCHES "^${IDRIS_MLIR_LLVM_SERIES}\\.")
			message(FATAL_ERROR "production builds require clang ${IDRIS_MLIR_LLVM_SERIES}.x (got ${CMAKE_${lang}_COMPILER_VERSION} for ${lang})")
		endif()
	endforeach()
endif()
# The target programs are compiled for is decided here and nowhere else. The
# preset names its triple (CMAKE_CXX_COMPILER_TARGET), which the runtime is
# built for too, and selects one entry below. idris-mlir writes the
# triple and CPU on every module as its #llvm.target, with LLVM's data
# layout, and every later step reads them there; every other fact of the
# target is one of the entry's, which the build hands to whatever needs it.
# An entry sets each of these:
#
#   IDRIS_MLIR_TARGET_CPU               the CPU programs are compiled for,
#                                       an LLVM name
#   IDRIS_MLIR_RUNTIME_BASELINE         the flags of the CPU runtime code is
#                                       compiled for, which every machine of
#                                       the target has (idris-mlir raises
#                                       it to the program's CPU)
#   IDRIS_MLIR_RUNTIME_CPU_TEST         the runtime's test of the processor
#                                       at a program's entry, the runtime's
#                                       unit for it (runtime/Platform/)
#   IDRIS_MLIR_RUNTIME_CPU_FEATURES     the features that test names, each
#                                       as the test spells it and as LLVM
#                                       does (a runtime/ header)
#   IDRIS_MLIR_RUNTIME_DEFINITIONS      what the vendored allocator is told
#                                       of the system (snmalloc's headers)
#   IDRIS_MLIR_RUNTIME_BITCODE_FLAGS    the flags that make each member of
#                                       the runtime's archive carry its
#                                       bitcode with its native code, which
#                                       joins every program's module
#   IDRIS_MLIR_RUNTIME_BITCODE_SECTION  the section of the prepared
#                                       runtime's object that holds the
#                                       bitcode and every link leaves out,
#                                       or "" for a file beside the object
#                                       (an object format with no such
#                                       section, Mach-O's)
#   IDRIS_MLIR_RUNTIME_SECTIONS         the flags that put each function and
#                                       datum in its own section, for the
#                                       linker to drop the unused ones, or
#                                       "" where the object's bitcode
#                                       forbids them (clang rejects
#                                       -ffunction-sections with
#                                       -fembed-bitcode)
#   IDRIS_MLIR_EXECUTABLE_FLAGS         the link flags that make a program an
#                                       executable of the target
#   IDRIS_MLIR_PROGRAM_LINK_FLAGS       the link flags that drop and fold
#                                       what no program needs twice
#   IDRIS_MLIR_GMP                      what links GMP: a flag or the path of
#                                       its archive
#   IDRIS_MLIR_NO_UNWINDER              the link flags that leave out the
#                                       unwinder, so that the runtime's link
#                                       check fails on a reference to it
#   IDRIS_MLIR_SYMBOL_PREFIX            what the object format puts before a
#                                       C name ("_" on Mach-O)
#   IDRIS_MLIR_CONSTRUCTOR_SECTIONS     the sections of an object that hold
#                                       static constructors and destructors,
#                                       which the runtime may not have
#   IDRIS_MLIR_CODEGEN_LIBRARY_CALLS    the library functions, beyond memcpy,
#                                       memset and memmove, that LLVM's code
#                                       for the target calls, the only calls
#                                       a program's object may make that its
#                                       source does not
#   IDRIS_MLIR_PAGE_SIZE                the size of a page of the target, the
#                                       one number the runtime's startup
#                                       check compares with the system's:
#                                       16384 on Darwin arm64, 4096 on Linux
#                                       x86-64. Nothing else may assume it.
#   IDRIS_MLIR_TOOL_COMPILE_FLAGS       the hardening our tools are compiled
#                                       with beyond the language profile's,
#                                       that the target has live
#   IDRIS_MLIR_TOOL_LINK_FLAGS          the link flags that make a tool an
#                                       executable of the target, hardened
#   IDRIS_MLIR_TOOL_RELEASE_LINK_FLAGS  the Release link's own flags, such
#                                       as dropping unused sections
#
# A program's link line is the pinned C compiler with its object, the
# runtime and -o, then idris-mlir --print-link-flags: --target with the
# triple, the executable flags, the program link flags and GMP.
if(CMAKE_CXX_COMPILER_TARGET MATCHES "^x86_64-[^-]+-linux-musl$")
	# x86-64-v3 (AVX2, BMI2, FMA) runs on every x86-64 CPU since Haswell
	# (2013) and AMD's Zen, and an executable names what an older one lacks.
	# snmalloc needs CMPXCHG16B, which the baseline lacks.
	# PIN(runtime-cx16) — see PINS.md
	set(IDRIS_MLIR_TARGET_CPU "x86-64-v3")
	set(IDRIS_MLIR_RUNTIME_BASELINE -march=x86-64 -mcx16)
	set(IDRIS_MLIR_RUNTIME_CPU_TEST Platform/X86_64/Cpu.cpp)
	set(IDRIS_MLIR_RUNTIME_CPU_FEATURES cpu_x86_64.h)
	set(IDRIS_MLIR_RUNTIME_DEFINITIONS SNMALLOC_HAS_LINUX_RANDOM_H SNMALLOC_HAS_LINUX_FUTEX_H)
	# ELF: fat LTO objects, and one object whose .llvm.lto section, as a fat
	# LTO object's, is excluded from every link.
	set(IDRIS_MLIR_RUNTIME_BITCODE_FLAGS -flto=full -ffat-lto-objects)
	set(IDRIS_MLIR_RUNTIME_BITCODE_SECTION ".llvm.lto")
	set(IDRIS_MLIR_RUNTIME_SECTIONS -ffunction-sections -fdata-sections)
	# Static-PIE on musl; GMP is the pinned sysroot's, which the pinned
	# clang's configuration file names.
	set(IDRIS_MLIR_EXECUTABLE_FLAGS -fuse-ld=lld -static-pie)
	set(IDRIS_MLIR_PROGRAM_LINK_FLAGS -Wl,--gc-sections -Wl,--icf=all)
	set(IDRIS_MLIR_GMP -lgmp)
	set(IDRIS_MLIR_NO_UNWINDER --unwindlib=none)
	set(IDRIS_MLIR_SYMBOL_PREFIX "")
	set(IDRIS_MLIR_CONSTRUCTOR_SECTIONS .init_array .fini_array .ctors .dtors .preinit_array)
	set(IDRIS_MLIR_CODEGEN_LIBRARY_CALLS "")
	set(IDRIS_MLIR_PAGE_SIZE 4096)
	# Our tools: PIE code with CET and stack-clash probes; static-PIE on musl,
	# read-only after relocation, no executable stack. PIN(musl-thread-stacks):
	# LLVM takes the libc's default thread stack, which musl reads from
	# PT_GNU_STACK — see PINS.md. The Release link drops unused sections
	# (lld's ELF spelling).
	set(IDRIS_MLIR_TOOL_COMPILE_FLAGS -fPIE -fcf-protection=full -fstack-clash-protection)
	set(IDRIS_MLIR_TOOL_LINK_FLAGS -static-pie LINKER:-z,relro LINKER:-z,now LINKER:-z,noexecstack
		LINKER:-z,nodlopen LINKER:-z,stack-size=8388608)
	set(IDRIS_MLIR_TOOL_RELEASE_LINK_FLAGS LINKER:--gc-sections)
elseif(CMAKE_CXX_COMPILER_TARGET MATCHES "^arm64-apple-macosx")
	# Apple Silicon: apple-m1 is the baseline every Apple CPU since the M1
	# has, and a program compiled for a later one names what an older lacks.
	# Function multiversioning tests the features at a program's entry, and
	# compiler-rt reads them from sysctl only when the test asks.
	set(IDRIS_MLIR_TARGET_CPU "apple-m1")
	set(IDRIS_MLIR_RUNTIME_BASELINE -mcpu=apple-m1)
	set(IDRIS_MLIR_RUNTIME_CPU_TEST Platform/Aarch64/Cpu.cpp)
	set(IDRIS_MLIR_RUNTIME_CPU_FEATURES cpu_aarch64.h)
	# snmalloc chooses its Apple platform itself (mach_vm, arc4random); the
	# Linux headers its defines name do not exist here.
	set(IDRIS_MLIR_RUNTIME_DEFINITIONS "")
	# Mach-O: each member carries its bitcode embedded (IRObjectFile reads
	# it), and the prepared runtime keeps the joined bitcode in a .bc file
	# beside its object, Mach-O having no section every link leaves out.
	# -fembed-bitcode rejects -ffunction-sections/-fdata-sections, and
	# Apple's default subsections_via_symbols already gives -dead_strip its
	# granularity, so the runtime's sections are left to the object format.
	set(IDRIS_MLIR_RUNTIME_BITCODE_FLAGS -fembed-bitcode=all)
	set(IDRIS_MLIR_RUNTIME_BITCODE_SECTION "")
	set(IDRIS_MLIR_RUNTIME_SECTIONS "")
	# A dynamic PIE against libSystem, linked by the pinned ld64.lld.
	set(IDRIS_MLIR_EXECUTABLE_FLAGS -fuse-ld=lld)
	set(IDRIS_MLIR_PROGRAM_LINK_FLAGS -Wl,-dead_strip -Wl,--icf=all)
	# The pinned clang's configuration file names the sysroot beside it;
	# GMP is its one library on Darwin. The path is derived from the
	# compiler the preset names, so a toolchain elsewhere still resolves.
	get_filename_component(IDRIS_MLIR_CLANG_BIN "${CMAKE_C_COMPILER}" DIRECTORY)
	get_filename_component(IDRIS_MLIR_TOOLCHAIN_ROOT "${IDRIS_MLIR_CLANG_BIN}/../.." ABSOLUTE)
	set(IDRIS_MLIR_GMP "${IDRIS_MLIR_TOOLCHAIN_ROOT}/sysroot/usr/lib/libgmp.a")
	# libSystem is the unwinder; there is no separate one to leave out.
	set(IDRIS_MLIR_NO_UNWINDER "")
	set(IDRIS_MLIR_SYMBOL_PREFIX "_")
	set(IDRIS_MLIR_CONSTRUCTOR_SECTIONS __mod_init_func __mod_term_func __init_offsets)
	set(IDRIS_MLIR_CODEGEN_LIBRARY_CALLS bzero memset_pattern16 __sincos_stret __sincosf_stret __exp10 __exp10f)
	set(IDRIS_MLIR_PAGE_SIZE 16384)
	# Our tools: Darwin's PIE executables need nothing beyond the profile.
	# PIN(darwin-inert-mitigations): branch protection executes as NOP in a
	# plain arm64 Darwin process — see PINS.md.
	set(IDRIS_MLIR_TOOL_COMPILE_FLAGS "")
	set(IDRIS_MLIR_TOOL_LINK_FLAGS "")
	set(IDRIS_MLIR_TOOL_RELEASE_LINK_FLAGS "")
else()
	message(FATAL_ERROR "no target entry for ${CMAKE_CXX_COMPILER_TARGET}: give it each fact the comment above the entries lists, in CMakeLists.txt")
endif()

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# No unit is a C++ module, so no target scans its sources for one.
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)

# Every C++ unit of the build, ours and the runtime's, is compiled as LLVM
# and MLIR are, without exceptions or RTTI, and against libc++'s extensive
# hardening. PIN(clang-no-reflection): no -freflection — see PINS.md
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
	message(FATAL_ERROR "production builds require the pinned libc++")
endif()

# Warnings are errors, for every target with our own C++ (the runtime too),
# in the typecheck build as in every preset: a slice that only printed
# them let through what the first real build then refused.
# PIN(clang-libcxx): a warning only GCC spells is left out; see PINS.md.
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
# build of our code is full LTO, linked with LLVM's and MLIR's libraries as
# the native code stage 2 built them.
add_library(idris_mlir_language_profile INTERFACE)
target_link_libraries(idris_mlir_language_profile INTERFACE idris_mlir_warnings)

target_compile_options(idris_mlir_language_profile INTERFACE
	-ffp-contract=off
	"$<$<CONFIG:Release>:-ffunction-sections;-fdata-sections;-flto=full>"
)
target_link_options(idris_mlir_language_profile INTERFACE
	"$<$<CONFIG:Release>:-flto=full>"
)

# What a preset adds to our tools' compiles and links, and to nothing else
# (the runtime has its own profile): the hardened preset's sanitizer traps
# and mitigations. Empty in the other presets.
set(IDRIS_MLIR_PRESET_COMPILE_FLAGS "" CACHE STRING "The flags the preset adds to every compile of our tools")
set(IDRIS_MLIR_PRESET_LINK_FLAGS "" CACHE STRING "The flags the preset adds to every link of our tools")
target_compile_options(idris_mlir_language_profile INTERFACE ${IDRIS_MLIR_PRESET_COMPILE_FLAGS})
target_link_options(idris_mlir_language_profile INTERFACE ${IDRIS_MLIR_PRESET_LINK_FLAGS})

# The target's own flags for our tools, from its entry above. FORTIFY is in
# neither: it is inert on musl and in Apple's SDK for C++
# (PIN(darwin-inert-mitigations) — see PINS.md).
target_compile_options(idris_mlir_language_profile INTERFACE ${IDRIS_MLIR_TOOL_COMPILE_FLAGS})
target_link_options(idris_mlir_language_profile INTERFACE
	${IDRIS_MLIR_TOOL_LINK_FLAGS}
	"$<$<CONFIG:Release>:${IDRIS_MLIR_TOOL_RELEASE_LINK_FLAGS}>"
)

# The runtime, then the dialect and its tools, which read where the
# runtime's archive is.
add_subdirectory(runtime)
add_subdirectory(foreign/idr)
