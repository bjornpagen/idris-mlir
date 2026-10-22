// RUN: idris-mlir-opt %s --idr-pipeline=to=owned 2>&1 | FileCheck %s
// RUN: %status 1 idris-mlir-opt %s -o /dev/null 2>&1 | FileCheck %s --check-prefix=ERR
// RUN: not idris-mlir-opt %s --verify-diagnostics 2>&1 | FileCheck %s --check-prefix=NOT
// NOTE: a capitalized word and a colon is no check line
// CHECK: holds
// CHECK-NEXT: holds too
// ERR: error
// NOT-NOT: crash
