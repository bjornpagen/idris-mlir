// RUN: idris-mlir-opt --help | FileCheck %s
// rule: DRV-OPT-1, OPT-PIPE-1
// CHECK-DAG: --idr-check-profile
// CHECK-DAG: --idr-defunctionalize
// CHECK-DAG: --idr-lower
// CHECK-DAG: --idr-pipeline
// CHECK-DAG: --idr-simplify
// CHECK-DAG: --idr-specialize
// CHECK-DAG: --idr-tail-loops
// CHECK-DAG: --convert-to-llvm
// CHECK-DAG: --inline
