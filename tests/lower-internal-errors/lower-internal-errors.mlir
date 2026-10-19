// RUN: idris-mlir-opt %s -verify-diagnostics --idr-lower -o /dev/null
// RUN: not idris-mlir-opt %s --idr-lower -o /dev/null 2>&1 | FileCheck %s
// RUN: sed 's/dense<\[32, 32, 32, 32\]>/dense<64>/' %s | idris-mlir-opt --idr-lower --idr-expect=holds=stage=lowered -o /dev/null
// What no Idris program reaches is the compiler's error, never a rejection
// (`unsupported (<reason>)`, which idris-mlir reports as the user's),
// whichever step finds it: the module's data layout is the target entry's,
// the one the runtime is built for, so a module of another (its pointers
// not the runtime's words) is refused at the module, by the program's own
// verifier before any pass runs. Its pointers are what it is refused for:
// the same module with 64-bit pointers, the runtime's words, lowers.
// CHECK-NOT: unsupported (
// CHECK: error: the module's target is not the runtime's

// expected-error @+1 {{the module's target is not the runtime's}}
module attributes {dlti.dl_spec = #dlti.dl_spec<!llvm.ptr = dense<[32, 32, 32, 32]> : vector<4xi64>>} { idr.program @"internal-errors" root(@Prog.main) stage(owned) {
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
} }

