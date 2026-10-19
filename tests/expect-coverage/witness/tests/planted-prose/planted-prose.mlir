// RUN: idris-mlir-opt %s --idr-expect='holds=in-prose' -o /dev/null
// in-prose holds of this module, which no failure shows
// RUN: not idris-mlir-opt %s --idr-expect='holds=prefixed-more' -o /dev/null 2>&1 | FileCheck %s
// CHECK: {{expected prefixed-more: }}
