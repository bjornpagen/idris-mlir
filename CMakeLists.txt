# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
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

# ccache (on PATH, or MacPorts') launches every C and C++ compile, on the
# cache tools/bootstrap.sh configures (.toolchain/ccache): a rebuild
# recompiles only what changed, in every preset and every checkout, as in
# the toolchain's builds. Each checkout
# names its own root as ccache's base directory, so every path under it is
# hashed relative to it and one checkout's compile is another's hit; the
# cache's settings (tools/bootstrap.sh) hash no build directory, which is
# right because no object holds it (-ffile-prefix-map, below), and
# tests/ccache-shared checks the hit. CMake copies the launcher onto
# each target created after it. The one precompiled header (the dialect's,
# foreign/idr/lib/IR) is cached as any compile is: the cache's settings
# take a header's defines and time macros as they are, and the header holds
# no timestamp (-fno-pch-timestamp, below), so the compile that makes it and
# every compile that reads it hit. The launcher changes nothing a compile
# produces.
find_program(IDRIS_MLIR_CCACHE ccache HINTS /opt/local/bin REQUIRED)
set(IDRIS_MLIR_CCACHE_LAUNCHER "${CMAKE_COMMAND}" -E env
	"CCACHE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.toolchain/ccache"
	"CCACHE_BASEDIR=${CMAKE_CURRENT_SOURCE_DIR}" "${IDRIS_MLIR_CCACHE}")
set(CMAKE_C_COMPILER_LAUNCHER ${IDRIS_MLIR_CCACHE_LAUNCHER})
set(CMAKE_CXX_COMPILER_LAUNCHER ${IDRIS_MLIR_CCACHE_LAUNCHER})

project(idris_mlir LANGUAGES C CXX)

# What a compile writes holds no path of the checkout it ran in: its debug
# info, its __FILE__s and its coverage name files relative to the
# checkout's root, so an object is the same whichever checkout built it.
add_compile_options("-ffile-prefix-map=${CMAKE_CURRENT_SOURCE_DIR}=.")

# The typecheck build (make typecheck, the typecheck preset, whose
# toolchain file tools/bootstrap.sh typecheck writes): every unit of
# foreign/idr compiled by the host's clang against the TableGen-only LLVM
# and MLIR, nothing linked but idris-mlir-tblgen, and the runtime's units
# compiled into objects nothing links. It checks that the code compiles
# where stage 2 is not built; it is no build of the compiler. The typecheck
# toolchain file sets it, so it is declared after project() has read that
# file.
option(IDRIS_MLIR_TYPECHECK "Compile foreign/idr with the host's clang against the TableGen-only LLVM/MLIR, and link nothing but idris-mlir-tblgen" OFF)

# PIN(platform-gate): the build runs on the machines whose targets the
# compiler has, Linux x86_64 and aarch64 and Darwin arm64, the same
# machines tools/bootstrap.sh builds a toolchain on.
if(NOT (CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|aarch64)$")
		AND NOT (CMAKE_SYSTEM_NAME STREQUAL "Darwin" AND CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64"))
	message(FATAL_ERROR "the machine boundary is Linux x86_64 and aarch64 and Darwin arm64 (got ${CMAKE_SYSTEM_NAME} ${CMAKE_SYSTEM_PROCESSOR})")
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
# built for too, and its toolchain file the page size (IDRIS_MLIR_PAGE_SIZE,
# the machine's that built the toolchain); the two select one entry below,
# which may decide other facts by the page size. idris-mlir writes the
# triple and the program's CPU on every module as its #llvm.target, with
# LLVM's data layout, and every later step reads them there; every other
# fact of the target is one of the entry's, which the build hands to
# whatever needs it. An entry sets each of these:
#
#   IDRIS_MLIR_PROGRAM_CPU              the pinned C compiler's flags for
#                                       the CPU programs are compiled for
#   IDRIS_MLIR_BASELINE_CPU             its flags for the CPU every machine
#                                       of the target has, which the
#                                       runtime is compiled for
#   IDRIS_MLIR_RUNTIME_CPU_TEST         the runtime's test of the processor
#                                       at a program's entry, the runtime's
#                                       unit for it (runtime/Platform/)
#   IDRIS_MLIR_RUNTIME_CPU_FEATURES     the features that test names, each
#                                       as the test spells it and as LLVM
#                                       does (a runtime/ header)
#   IDRIS_MLIR_RUNTIME_OS               the runtime's unit for what the host
#                                       decides by its operating system
#                                       (runtime/Platform/)
#   IDRIS_MLIR_RUNTIME_SIMDUTF          the one simdutf implementation the
#                                       runtime calls, whose kernels use
#                                       only the program CPU's features
#   IDRIS_MLIR_RUNTIME_BITCODE_FLAGS    the flags that make each member of
#                                       the runtime's archive carry its
#                                       bitcode with its native code, which
#                                       joins every program's module
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
#   IDRIS_MLIR_RED_ZONE_BYTES           the bytes below the stack pointer a
#                                       leaf may use without moving it,
#                                       which code generation leaves out of
#                                       the frame it reports
#   IDRIS_MLIR_TOOL_STACK_BYTES,        the tools' stack, signal stack and
#   IDRIS_MLIR_TOOL_SIGNAL_BYTES,       the outside code's margin, each
#   IDRIS_MLIR_OUTSIDE_STACK_BYTES      measured on the target (below)
#   IDRIS_MLIR_TOOL_COMPILE_FLAGS       the hardening our tools are compiled
#                                       with beyond the language profile's,
#                                       that the target has live
#   IDRIS_MLIR_TOOL_LINK_FLAGS          the link flags that make a tool an
#                                       executable of the target, hardened
#   IDRIS_MLIR_TOOL_RELEASE_LINK_FLAGS  the Release link's own flags, such
#                                       as dropping unused sections
#
# The page size, which the toolchain file names and no entry sets, is the
# one number the runtime's startup check compares with the system's: 16384
# on Darwin arm64 and on 16 KiB arm64 Linux, 4096 on x86-64 and on 4 KiB
# arm64 Linux. Nothing else may assume it.
#
# A program's link line is the pinned C compiler with its object, the
# runtime and -o, then idris-mlir --print-link-flags: --target with the
# triple, the executable flags, the program link flags and GMP, the
# sysroot's archive beside the pinned clang on every target. Its path is
# derived from the compiler the preset names, so a toolchain elsewhere
# still resolves.
get_filename_component(IDRIS_MLIR_CLANG_BIN "${CMAKE_C_COMPILER}" DIRECTORY)
get_filename_component(IDRIS_MLIR_TOOLCHAIN_ROOT "${IDRIS_MLIR_CLANG_BIN}/../.." ABSOLUTE)
set(IDRIS_MLIR_GMP "${IDRIS_MLIR_TOOLCHAIN_ROOT}/sysroot/usr/lib/libgmp.a")
# The tools' stacks are measured on each target, never chosen. A tool's
# threads run on IDRIS_MLIR_TOOL_STACK_BYTES plus
# IDRIS_MLIR_OUTSIDE_STACK_BYTES, and their signal stacks on
# IDRIS_MLIR_TOOL_SIGNAL_BYTES plus the same margin: the runner adds the
# margin to a tool's plan as it does to a program's, whose own stack the
# compiler computes (runtime/Start/Runner.cpp). No target has measured them
# yet, so each entry declares them with this: each a cache variable with no
# default, and configuring refuses until all three are given. Once a
# target's are measured, its entry sets each to its number in place of the
# call, beside the build and the input it was measured on. What is
# measured, on the target's own machine, with the release preset's tools:
#   IDRIS_MLIR_TOOL_STACK_BYTES     the deepest byte written on any thread of
#                                   idris-mlir, idris-mlir-opt and
#                                   idris-mlir-reduce (the main thread and
#                                   every pool worker), each stack painted
#                                   before it runs, on the stage-1 module
#                                   (tools/self.sh 1) and on
#                                   tests/scale-nesting and
#                                   tests/scale-nesting-source at their full
#                                   depth; at most half of UINT_MAX, as LLVM
#                                   sizes a thread's stack in an unsigned
#   IDRIS_MLIR_TOOL_SIGNAL_BYTES    the deepest byte written on a painted
#                                   signal stack, the main thread's and a
#                                   worker's, while the runtime's fault
#                                   handler and LLVM's crash report run on
#                                   it: the same tools, each made to reach
#                                   its stack's guard
#   IDRIS_MLIR_OUTSIDE_STACK_BYTES  the deepest stack an entry of the C
#                                   library, GMP or compiler-rt takes from
#                                   its call, painted, over every such entry
#                                   the runtime and the tools call, on the
#                                   same runs and on the program suite
#                                   (make test); the margin programs take
#                                   too
# The build that measures is configured with sizes it knows cover its runs;
# those are the instrument's, and are never recorded. Until an entry holds
# its numbers, every configure on the target is given provisional sizes,
# typecheck's too; the Makefile's opening comment says how each command
# takes them.
function(idris_mlir_unmeasured_stacks)
	foreach(size IDRIS_MLIR_TOOL_STACK_BYTES IDRIS_MLIR_TOOL_SIGNAL_BYTES IDRIS_MLIR_OUTSIDE_STACK_BYTES)
		set(${size} "" CACHE STRING "Bytes, measured on the target as CMakeLists.txt says above its target entries")
		if(NOT "${${size}}" MATCHES "^[1-9][0-9]*$")
			message(FATAL_ERROR "${size} is not measured for ${CMAKE_CXX_COMPILER_TARGET} with ${IDRIS_MLIR_PAGE_SIZE}-byte pages: measure it as CMakeLists.txt says above its target entries and record it in the entry, or give it provisionally as the Makefile's opening comment says (make help)")
		endif()
	endforeach()
endfunction()
if(CMAKE_CXX_COMPILER_TARGET MATCHES "-linux-gnu$")
	# Linux: ELF executables linked against glibc, the system's C library,
	# dynamically, and against everything else statically, by the pinned
	# lld. snmalloc takes its entropy and its waits from the kernel's
	# headers, which the system's C library ships beside its own.
	set(IDRIS_MLIR_RUNTIME_OS Platform/Linux/Host.cpp)
	# ELF: fat LTO objects.
	set(IDRIS_MLIR_RUNTIME_BITCODE_FLAGS -flto=full -ffat-lto-objects)
	set(IDRIS_MLIR_RUNTIME_SECTIONS -ffunction-sections -fdata-sections)
	# A PIE against glibc, the driver's default.
	set(IDRIS_MLIR_EXECUTABLE_FLAGS -fuse-ld=lld)
	set(IDRIS_MLIR_PROGRAM_LINK_FLAGS -Wl,--gc-sections -Wl,--icf=all)
	set(IDRIS_MLIR_NO_UNWINDER --unwindlib=none)
	set(IDRIS_MLIR_SYMBOL_PREFIX "")
	set(IDRIS_MLIR_CONSTRUCTOR_SECTIONS .init_array .fini_array .ctors .dtors .preinit_array)
	set(IDRIS_MLIR_CODEGEN_LIBRARY_CALLS "")
	# Our tools: glibc's fortified functions where they are compiled with
	# the optimization those need (Release); bound at load, read-only after
	# relocation, no executable stack. The Release link drops unused
	# sections (lld's ELF spelling).
	set(IDRIS_MLIR_TOOL_FORTIFY "$<$<CONFIG:Release>:-D_FORTIFY_SOURCE=3>")
	set(IDRIS_MLIR_TOOL_LINK_FLAGS LINKER:-z,relro LINKER:-z,now LINKER:-z,noexecstack LINKER:-z,nodlopen)
	set(IDRIS_MLIR_TOOL_RELEASE_LINK_FLAGS LINKER:--gc-sections)
endif()
if(CMAKE_CXX_COMPILER_TARGET MATCHES "^x86_64-[^-]+-linux-gnu$" AND IDRIS_MLIR_PAGE_SIZE EQUAL 4096)
	# x86-64-v3 (AVX2, BMI2, FMA) runs on every x86-64 CPU since Haswell
	# (2013) and AMD's Zen, and an executable names what an older one lacks.
	# snmalloc needs CMPXCHG16B, which the baseline lacks.
	# PIN(runtime-cx16) — see PINS.md
	set(IDRIS_MLIR_PROGRAM_CPU -march=x86-64-v3)
	set(IDRIS_MLIR_BASELINE_CPU -march=x86-64 -mcx16)
	set(IDRIS_MLIR_RUNTIME_CPU_TEST Platform/X86_64/Cpu.cpp)
	set(IDRIS_MLIR_RUNTIME_CPU_FEATURES cpu_x86_64.h)
	# Haswell's kernels use AVX2 and BMI2, which x86-64-v3 has.
	set(IDRIS_MLIR_RUNTIME_SIMDUTF haswell)
	# The System V ABI keeps the 128 bytes below the stack pointer for a
	# leaf, and LLVM's code uses them.
	set(IDRIS_MLIR_RED_ZONE_BYTES 128)
	idris_mlir_unmeasured_stacks()
	# Our tools: PIE code with CET.
	set(IDRIS_MLIR_TOOL_COMPILE_FLAGS -fPIE -fcf-protection=full ${IDRIS_MLIR_TOOL_FORTIFY})
elseif(CMAKE_CXX_COMPILER_TARGET MATCHES "^aarch64-[^-]+-linux-gnu$" AND IDRIS_MLIR_PAGE_SIZE EQUAL 4096)
	# arm64 Linux on the kernel's default 4 KiB pages: every 64-bit
	# Raspberry Pi before the 5 (Zero 2 W, 3, 4), Graviton, Ampere,
	# Snapdragon X, Linux in a VM on a Mac. generic is armv8-a, which the
	# Pis' Cortex-A53 and A72 are, and a program compiled for a later CPU
	# names what an older one lacks.
	set(IDRIS_MLIR_PROGRAM_CPU -mcpu=generic)
	set(IDRIS_MLIR_BASELINE_CPU -march=armv8-a)
	set(IDRIS_MLIR_RUNTIME_CPU_TEST Platform/Aarch64/Cpu.cpp)
	set(IDRIS_MLIR_RUNTIME_CPU_FEATURES cpu_aarch64.h)
	set(IDRIS_MLIR_RUNTIME_SIMDUTF arm64)
	# The procedure call standard keeps nothing below the stack pointer, and
	# LLVM's code uses nothing there.
	set(IDRIS_MLIR_RED_ZONE_BYTES 0)
	idris_mlir_unmeasured_stacks()
	# Our tools: PIE code with branch protection (PAC and BTI, live on Linux
	# where the CPU has them and NOPs where it does not).
	set(IDRIS_MLIR_TOOL_COMPILE_FLAGS -fPIE -mbranch-protection=standard ${IDRIS_MLIR_TOOL_FORTIFY})
elseif(CMAKE_CXX_COMPILER_TARGET MATCHES "^aarch64-[^-]+-linux-gnu$" AND IDRIS_MLIR_PAGE_SIZE EQUAL 16384)
	# arm64 Linux on 16 KiB pages: the Raspberry Pi 5 family under Raspberry
	# Pi OS, and Apple Silicon under Linux. cortex-a76 is the Pi 5's core
	# (ARMv8.2-A with crypto, dot product, RCpc, fp16 and SSBS), whose
	# features every Apple CPU has, so it is the baseline too, as apple-m1
	# is on Darwin.
	set(IDRIS_MLIR_PROGRAM_CPU -mcpu=cortex-a76)
	set(IDRIS_MLIR_BASELINE_CPU -mcpu=cortex-a76)
	set(IDRIS_MLIR_RUNTIME_CPU_TEST Platform/Aarch64/Cpu.cpp)
	set(IDRIS_MLIR_RUNTIME_CPU_FEATURES cpu_aarch64.h)
	set(IDRIS_MLIR_RUNTIME_SIMDUTF arm64)
	# The procedure call standard keeps nothing below the stack pointer, and
	# LLVM's code uses nothing there.
	set(IDRIS_MLIR_RED_ZONE_BYTES 0)
	idris_mlir_unmeasured_stacks()
	set(IDRIS_MLIR_TOOL_COMPILE_FLAGS -fPIE -mbranch-protection=standard ${IDRIS_MLIR_TOOL_FORTIFY})
elseif(CMAKE_CXX_COMPILER_TARGET MATCHES "^arm64-apple-macosx" AND IDRIS_MLIR_PAGE_SIZE EQUAL 16384)
	# Apple Silicon: apple-m1 is the baseline every Apple CPU since the M1
	# has, and a program compiled for a later one names what an older lacks.
	# Function multiversioning tests the features at a program's entry, and
	# compiler-rt reads them from sysctl only when the test asks.
	set(IDRIS_MLIR_PROGRAM_CPU -mcpu=apple-m1)
	set(IDRIS_MLIR_BASELINE_CPU -mcpu=apple-m1)
	set(IDRIS_MLIR_RUNTIME_CPU_TEST Platform/Aarch64/Cpu.cpp)
	set(IDRIS_MLIR_RUNTIME_CPU_FEATURES cpu_aarch64.h)
	set(IDRIS_MLIR_RUNTIME_SIMDUTF arm64)
	# snmalloc chooses its Apple platform itself (mach_vm, arc4random); the
	# Linux headers its defines name do not exist here.
	set(IDRIS_MLIR_RUNTIME_OS Platform/Darwin/Host.cpp)
	# Mach-O: each member carries its bitcode embedded (IRObjectFile reads
	# it). -fembed-bitcode rejects -ffunction-sections/-fdata-sections, and
	# Apple's default subsections_via_symbols already gives -dead_strip its
	# granularity, so the runtime's sections are left to the object format.
	set(IDRIS_MLIR_RUNTIME_BITCODE_FLAGS -fembed-bitcode=all)
	set(IDRIS_MLIR_RUNTIME_SECTIONS "")
	# A dynamic PIE against libSystem, linked by the pinned ld64.lld.
	set(IDRIS_MLIR_EXECUTABLE_FLAGS -fuse-ld=lld)
	set(IDRIS_MLIR_PROGRAM_LINK_FLAGS -Wl,-dead_strip -Wl,--icf=all)
	# libSystem is the unwinder; there is no separate one to leave out.
	set(IDRIS_MLIR_NO_UNWINDER "")
	set(IDRIS_MLIR_SYMBOL_PREFIX "_")
	set(IDRIS_MLIR_CONSTRUCTOR_SECTIONS __mod_init_func __mod_term_func __init_offsets)
	set(IDRIS_MLIR_CODEGEN_LIBRARY_CALLS bzero memset_pattern16 __sincos_stret __sincosf_stret __exp10 __exp10f)
	# Apple's ABI keeps the 128 bytes below the stack pointer for a leaf,
	# though LLVM's code for arm64 uses none of them: the bound takes what
	# the ABI allows.
	set(IDRIS_MLIR_RED_ZONE_BYTES 128)
	idris_mlir_unmeasured_stacks()
	# Our tools: Darwin's PIE executables need nothing beyond the profile.
	# PIN(darwin-inert-mitigations): branch protection executes as NOP in a
	# plain arm64 Darwin process — see PINS.md.
	set(IDRIS_MLIR_TOOL_COMPILE_FLAGS "")
	set(IDRIS_MLIR_TOOL_LINK_FLAGS "")
	set(IDRIS_MLIR_TOOL_RELEASE_LINK_FLAGS "")
else()
	message(FATAL_ERROR "no target entry for ${CMAKE_CXX_COMPILER_TARGET} with ${IDRIS_MLIR_PAGE_SIZE}-byte pages: give it each fact the comment above the entries lists, in CMakeLists.txt")
endif()
# Each CPU as the code generator reads it, an LLVM CPU name and features,
# derived once, here, from the entry's flags by the C compiler that compiles
# the runtime with them: what it writes on a function it compiles with
# them, with nothing of its own, is what every runtime function it compiles
# has (idris-mlir parses that of each). This is the target's one
# description of a CPU: idris-mlir compiles programs for the program's,
# whose features are its flags' and then the baseline's (which every
# machine has, and the runtime's code may use), so that no program CPU
# lacks what the runtime was compiled to use; and the runtime's functions
# take the program's (foreign/idr/lib/Driver/ReadRuntime.cpp).
file(WRITE "${CMAKE_BINARY_DIR}/cpu-probe.cpp" "void idris_mlir_cpu_probe() {}\n")
function(idris_mlir_cpu out)
	execute_process(
		COMMAND "${CMAKE_CXX_COMPILER}" "--target=${CMAKE_CXX_COMPILER_TARGET}" ${ARGN}
			-O3 -S -emit-llvm -o - "${CMAKE_BINARY_DIR}/cpu-probe.cpp"
		OUTPUT_VARIABLE ir ERROR_VARIABLE error RESULT_VARIABLE status)
	if(NOT status EQUAL 0 OR NOT ir MATCHES "\"target-cpu\"=\"([^\"]*)\"")
		message(FATAL_ERROR "${CMAKE_CXX_COMPILER} names no CPU for the flags ${ARGN}: ${error}")
	endif()
	set(${out}_NAME "${CMAKE_MATCH_1}" PARENT_SCOPE)
	set(features "")
	if(ir MATCHES "\"target-features\"=\"([^\"]*)\"")
		string(REPLACE "," ";" features "${CMAKE_MATCH_1}")
	endif()
	set(${out}_FEATURES "${features}" PARENT_SCOPE)
endfunction()
idris_mlir_cpu(IDRIS_MLIR_BASELINE_CPU ${IDRIS_MLIR_BASELINE_CPU})
idris_mlir_cpu(IDRIS_MLIR_PROGRAM_CPU ${IDRIS_MLIR_PROGRAM_CPU})
# The baseline's last: LLVM reads a later feature over an earlier one.
list(REMOVE_ITEM IDRIS_MLIR_PROGRAM_CPU_FEATURES ${IDRIS_MLIR_BASELINE_CPU_FEATURES})
list(APPEND IDRIS_MLIR_PROGRAM_CPU_FEATURES ${IDRIS_MLIR_BASELINE_CPU_FEATURES})
list(JOIN IDRIS_MLIR_BASELINE_CPU_FEATURES "," IDRIS_MLIR_BASELINE_CPU_FEATURES)
list(JOIN IDRIS_MLIR_PROGRAM_CPU_FEATURES "," IDRIS_MLIR_PROGRAM_CPU_FEATURES)

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

# The language profile of our tools. No FP contraction anywhere. Every
# frame is probed a page at a time on every target, so no frame of a tool
# steps over the one-page guard below its stack (idr/Driver/Tool.h): the
# pinned clang probes on Darwin as on Linux. The Release build of our code
# is full LTO, linked with LLVM's and MLIR's libraries as the native code
# stage 2 built them. The precompiled header our libraries share
# (foreign/idr/lib/IR) holds no timestamp, so the compile cache takes it,
# and every compile that reads it, by content.
add_library(idris_mlir_language_profile INTERFACE)
target_link_libraries(idris_mlir_language_profile INTERFACE idris_mlir_warnings)

target_compile_options(idris_mlir_language_profile INTERFACE
	-ffp-contract=off
	-fstack-clash-protection
	"$<$<COMPILE_LANGUAGE:CXX>:SHELL:-Xclang -fno-pch-timestamp>"
	"$<$<CONFIG:Release>:-ffunction-sections;-fdata-sections;-flto=full>"
)
target_link_options(idris_mlir_language_profile INTERFACE
	"$<$<CONFIG:Release>:-flto=full>"
)

# The target's own flags for our tools, from its entry above. FORTIFY is
# the Linux entries': it is inert in Apple's SDK for C++
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
