// RUN: idris-mlir-opt %s --idr-pipeline=to=owned --verify-each=false | FileCheck %s
// CHECK: idr.inc
