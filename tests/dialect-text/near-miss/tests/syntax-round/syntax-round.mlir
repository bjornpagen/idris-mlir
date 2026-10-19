// RUN: idris-mlir-opt %s -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// CHECK: idr.program
