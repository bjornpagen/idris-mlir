// RUN: not idris-mlir-opt %s --idr-pipeline=to=owned | FileCheck %s
// CHECK: idr.inc
