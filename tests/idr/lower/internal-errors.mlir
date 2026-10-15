// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics --idr-lower -o /dev/null
// RUN: not idris-mlir-opt %s -split-input-file --idr-lower -o /dev/null 2>&1 | FileCheck %s
// NEEDS-ACCEPTANCE: the text of the alignment error is C16's (section 4.1); check it against idr-lower.
// What no Idris program reaches is the compiler's error, never a rejection
// (`unsupported (<reason>)`, which idris-mlir reports as the user's): the
// module's data layout is the target entry's, the one the runtime is
// built for, and a buffer is a cell of the runtime, whose elements start
// eight bytes aligned and no more, so bufferization never asks for more.
// CHECK-NOT: unsupported (
// CHECK: error: the module's target is not the runtime's
// CHECK: error: {{.*}}alignment

// expected-error @+1 {{the module's target is not the runtime's: its pointers take 4 bytes at an alignment of 4, and the runtime's object slots are words of 8}}
module attributes {dlti.dl_spec = #dlti.dl_spec<!llvm.ptr = dense<[32, 32, 32, 32]> : vector<4xi64>>} {
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

idr.func private @wide(%n: index) -> memref<?xf64> {
  // expected-error @+2 {{alignment}}
  // expected-error @+1 {{failed to legalize operation 'memref.alloc'}}
  %b = memref.alloc(%n) {alignment = 64 : i64} : memref<?xf64>
  return %b : memref<?xf64>
}
