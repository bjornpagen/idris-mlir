// RUN: not idris-mlir-opt %s --idr-expect='holds=failing,everywhere=@f,piped,harnessed' -o /dev/null 2>&1 | FileCheck %s
// CHECK: {{expected failing: }}
// CHECK: {{expected everywhere: }}
// CHECK: {{expected piped: }}
// CHECK: {{expected harnessed: }}
