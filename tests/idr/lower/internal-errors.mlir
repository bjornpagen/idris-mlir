// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics --idr-lower -o /dev/null
// RUN: not idris-mlir-opt %s -split-input-file --idr-lower -o /dev/null 2>&1 | FileCheck %s
// NEEDS-ACCEPTANCE: the text of the alignment error; check it against idr-lower.
// What no Idris program reaches is the compiler's error, never a rejection
// (`unsupported (<reason>)`, which idris-mlir reports as the user's),
// whichever step finds it: the module's data layout is the target entry's,
// the one the runtime is built for, so a module of another (its pointers
// not the runtime's words) is refused at the module, by the program's own
// verifier before any pass runs; and a buffer is a cell of the runtime,
// whose elements start eight bytes aligned and no more, so bufferization
// never asks for more, and the lowering refuses a buffer that does.
// CHECK-NOT: unsupported (
// CHECK: error: the module's target is not the runtime's
// CHECK: error: {{.*}}alignment

// expected-error @+1 {{the module's target is not the runtime's: its pointers take 4 bytes at an alignment of 4, and the runtime's object slots are words of 8}}
module attributes {dlti.dl_spec = #dlti.dl_spec<!llvm.ptr = dense<[32, 32, 32, 32]> : vector<4xi64>>} { idr.program @"internal-errors" root(@Prog.main) stage(owned) {
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
} }

// -----

idr.program @"internal-errors" root(@root) stage(owned) {
  idr.func @wide(%n: index) -> memref<?xf64> {
    // expected-error @+2 {{alignment}}
    // expected-error @+1 {{failed to legalize operation 'memref.alloc'}}
    %b = memref.alloc(%n) {alignment = 64 : i64} : memref<?xf64>
    return %b : memref<?xf64>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
