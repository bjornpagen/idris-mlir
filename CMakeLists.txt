cmake_minimum_required(VERSION 3.20)
project(idris_mlir VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/toolchain.lock.json" TOOLCHAIN_LOCK)
string(JSON REQUIRED_LLVM_VERSION GET "${TOOLCHAIN_LOCK}" llvm version)
find_package(MLIR REQUIRED CONFIG)
if(NOT "${LLVM_PACKAGE_VERSION}" STREQUAL "${REQUIRED_LLVM_VERSION}")
  message(FATAL_ERROR
    "Expected LLVM ${REQUIRED_LLVM_VERSION}, found ${LLVM_PACKAGE_VERSION}")
endif()

list(APPEND CMAKE_MODULE_PATH "${MLIR_CMAKE_DIR}" "${LLVM_CMAKE_DIR}")
include(AddLLVM)
include(AddMLIR)
include(HandleLLVMOptions)
include_directories(SYSTEM ${LLVM_INCLUDE_DIRS} ${MLIR_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

add_subdirectory(compiler)
include(CTest)
if(BUILD_TESTING)
  find_package(Python3 3.9 REQUIRED COMPONENTS Interpreter)
  add_test(NAME mlir-driver
    COMMAND "${Python3_EXECUTABLE}"
      "${CMAKE_CURRENT_SOURCE_DIR}/tests/mlir/check_driver.py"
      "$<TARGET_FILE:idris-mlir-opt>"
      "${CMAKE_CURRENT_SOURCE_DIR}/tests/mlir/scalar.mlir")
endif()
