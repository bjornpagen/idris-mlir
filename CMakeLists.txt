cmake_minimum_required(VERSION 4.0)

# The configure gate (TC-CPP-1, adopted from bjornpagen/cpp-starter). The
# accepted toolchain series live in toolchain.lock.json only (TC-DEV-2).
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/toolchain.lock.json" IDRIS_MLIR_LOCK)
string(JSON IDRIS_MLIR_NINJA_SERIES GET "${IDRIS_MLIR_LOCK}" ninja accept)
string(JSON IDRIS_MLIR_CMAKE_SERIES GET "${IDRIS_MLIR_LOCK}" cmake accept)
string(JSON IDRIS_MLIR_GCC_SERIES GET "${IDRIS_MLIR_LOCK}" gcc accept)

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

# PIN(platform-gate-x86_64): cpp-starter's platforms plus Linux x86_64 (TC-DEV-1)
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

option(IDRIS_MLIR_LINT_GRAPH
	"Configure the reflection-free Clang lint graph instead of the GCC production graph"
	OFF
)
option(IDRIS_MLIR_RUNTIME_SANITIZERS
	"Use runtime ASan+UBSan instead of trap-mode UBSan (the asan-ubsan preset)"
	OFF
)

if(IDRIS_MLIR_LINT_GRAPH)
	# PIN(lint-graph-unbuilt): the pinned LLVM is built without clang — see PINS.md
	message(FATAL_ERROR "the lint graph needs clang and clang-tidy from the pinned LLVM, which this toolchain does not build yet (PINS.md: lint-graph-unbuilt)")
endif()

if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
	message(FATAL_ERROR "production builds require the pinned GCC toolchain (got ${CMAKE_CXX_COMPILER_ID})")
endif()
if(NOT CMAKE_CXX_COMPILER_VERSION MATCHES "^${IDRIS_MLIR_GCC_SERIES}\\."
		OR CMAKE_CXX_COMPILER_VERSION VERSION_LESS 16.1)
	message(FATAL_ERROR "production builds require GCC ${IDRIS_MLIR_GCC_SERIES}.x, at least 16.1 (got ${CMAKE_CXX_COMPILER_VERSION})")
endif()

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_MODULE_STD ON)

# Module-ABI flags must be global: CMake's synthesized import-std targets see
# only CMAKE_CXX_FLAGS, and the std module BMI must match every importer.
string(APPEND CMAKE_CXX_FLAGS " -fno-exceptions -fno-rtti -D_GLIBCXX_ASSERTIONS")

# IPO probe must precede -freflection: the probe TU is not compiled as C++26.
include(CheckIPOSupported)
check_ipo_supported(LANGUAGES CXX)
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)
string(APPEND CMAKE_CXX_FLAGS " -freflection")

# Binaries built with the pinned GCC find its libstdc++.
get_filename_component(IDRIS_MLIR_GCC_BIN "${CMAKE_CXX_COMPILER}" DIRECTORY)
set(CMAKE_BUILD_RPATH "${IDRIS_MLIR_GCC_BIN}/../lib64")

add_library(idris_mlir_language_profile INTERFACE)

if(NOT IDRIS_MLIR_RUNTIME_SANITIZERS)
	target_compile_options(idris_mlir_language_profile INTERFACE
		-fsanitize=undefined
		-fsanitize-trap=all
		"$<$<CONFIG:Release>:-ffunction-sections;-fdata-sections>"
	)
	target_link_options(idris_mlir_language_profile INTERFACE
		-fsanitize=undefined
		-fsanitize-trap=all
		"$<$<AND:$<CONFIG:Release>,$<BOOL:${IDRIS_MLIR_LINUX}>>:LINKER:--gc-sections>"
	)
endif()

target_compile_options(idris_mlir_language_profile INTERFACE
	-ftrivial-auto-var-init=zero
	-fstack-protector-strong
	-fzero-call-used-regs=used-gpr
	-fstack-clash-protection
	-fno-delete-null-pointer-checks
	-fno-strict-aliasing
	-fstrict-flex-arrays=3
	-fzero-init-padding-bits=all
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
	-Wuseless-cast
	-Wduplicated-branches
	-Wduplicated-cond
	-Wlogical-op
	-Wtrampolines
	-Wbidi-chars=any
)

# PIN(darwin-inert-mitigations): FORTIFY and branch protection are Linux-only — see PINS.md
if(IDRIS_MLIR_LINUX)
	# PIN(platform-gate-x86_64): x86_64 uses CET where arm64 uses PAC/BTI
	target_compile_options(idris_mlir_language_profile INTERFACE
		-fPIE
		"$<IF:$<STREQUAL:${CMAKE_SYSTEM_PROCESSOR},x86_64>,-fcf-protection=full,-mbranch-protection=standard>"
	)
	target_link_options(idris_mlir_language_profile INTERFACE
		-pie
		LINKER:-z,relro
		LINKER:-z,now
		LINKER:-z,noexecstack
		LINKER:-z,nodlopen
		LINKER:--as-needed
		LINKER:--no-copy-dt-needed-entries
	)
	if(NOT IDRIS_MLIR_RUNTIME_SANITIZERS)
		target_compile_options(idris_mlir_language_profile INTERFACE
			-U_FORTIFY_SOURCE
			-D_FORTIFY_SOURCE=3
		)
	endif()
endif()

# Dialect code (named modules only; empty until code exists that does not
# touch the MLIR API) and quarantine code (TC-ZONE-*).
add_subdirectory(src)
add_subdirectory(unsafe)
add_subdirectory(foreign/idr)
