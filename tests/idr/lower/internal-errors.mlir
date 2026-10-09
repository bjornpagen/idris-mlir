// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics --idr-lower -o /dev/null
// RUN: not idris-mlir-opt %s -split-input-file --idr-lower -o /dev/null 2>&1 | FileCheck %s
// What no Idris program reaches is the compiler's error, never a rejection
// (`unsupported (<reason>)`, which idris-mlir reports as the user's):
// the module's data layout is the target entry's, the one the runtime is
// built for, and Emit asks an array only for its dimension 0.
// CHECK-NOT: unsupported (
// CHECK: error: the module's target is not the runtime's
// CHECK: error: takes a dimension of an array other than the constant 0
// CHECK: error: takes the dimension of 'memref<?x?xi64>', which is not an array

// expected-error @+1 {{the module's target is not the runtime's: its pointers take 4 bytes at an alignment of 4, and the runtime's object slots are words of 8}}
module attributes {dlti.dl_spec = #dlti.dl_spec<!llvm.ptr = dense<[32, 32, 32, 32]> : vector<4xi64>>} {
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

func.func private @length(%a: memref<?xi64>, %i: index) -> index {
  // expected-error @+2 {{takes a dimension of an array other than the constant 0, and an array has the one dimension 0}}
  // expected-error @+1 {{failed to legalize operation 'memref.dim'}}
  %n = memref.dim %a, %i : memref<?xi64>
  return %n : index
}
func.func @Prog.main() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}

// -----

func.func private @length(%a: memref<?x?xi64>) -> index {
  %c0 = arith.constant 0 : index
  // expected-error @+2 {{takes the dimension of 'memref<?x?xi64>', which is not an array}}
  // expected-error @+1 {{failed to legalize operation 'memref.dim'}}
  %n = memref.dim %a, %c0 : memref<?x?xi64>
  return %n : index
}
func.func @Prog.main() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
