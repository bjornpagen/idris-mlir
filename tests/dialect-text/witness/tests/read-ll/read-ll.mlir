// RUN: idris-mlir %s -o %t
// RUN: FileCheck %s < %t.ll
// CHECK: ret
