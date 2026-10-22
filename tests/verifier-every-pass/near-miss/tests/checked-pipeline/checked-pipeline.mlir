// RUN: idris-mlir-opt %s --idr-pipeline=to=owned --verify-each=true | FileCheck %s
// RUN: idris-mlir-opt %s --verify-each=1 -o /dev/null
// CHECK: idr.inc
