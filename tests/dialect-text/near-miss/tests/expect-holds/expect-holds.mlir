// RUN: idris-mlir-opt %s --idr-expect='holds=allocation' -o /dev/null
// RUN: idris-mlir-opt %s --mlir-print-op-generic -o %t.mlir && idris-mlir-opt %t.mlir -o /dev/null
