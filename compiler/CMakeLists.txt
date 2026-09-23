add_llvm_executable(idris-mlir-opt tools/idris-mlir-opt.cpp)
llvm_update_compile_flags(idris-mlir-opt)
target_link_libraries(idris-mlir-opt PRIVATE
  MLIROptLib
  MLIRArithDialect
  MLIRFuncDialect
  MLIRTransforms
)
mlir_check_all_link_libraries(idris-mlir-opt)
