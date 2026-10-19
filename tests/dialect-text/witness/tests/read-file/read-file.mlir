// RUN: idris-mlir-opt %s -o %t.mlir
// RUN: FileCheck %s --check-prefix=OUT < %t.mlir
// OUT: idr.dec
