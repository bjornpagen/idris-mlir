# The reproducer, built against the pinned MLIR:
#   cmake -G Ninja -DMLIR_DIR=<prefix>/lib/cmake/mlir -B build && ninja -C build
cmake_minimum_required(VERSION 3.20)
project(uplift-final-counter CXX)
find_package(MLIR REQUIRED CONFIG)
set(CMAKE_CXX_STANDARD 17)
add_executable(uplift uplift.cpp)
target_include_directories(uplift PRIVATE ${LLVM_INCLUDE_DIRS} ${MLIR_INCLUDE_DIRS})
separate_arguments(DEFINITIONS NATIVE_COMMAND ${LLVM_DEFINITIONS})
target_compile_definitions(uplift PRIVATE ${DEFINITIONS})
target_compile_options(uplift PRIVATE -fno-rtti)
target_link_libraries(uplift PRIVATE MLIRSCFTransforms MLIRParser)
