// RUN: not idris-mlir-opt %s --idr-expect='holds=failing' -o /dev/null 2>&1 | FileCheck %s
// CHECK: {{expected failing: }}
