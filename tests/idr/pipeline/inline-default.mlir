// RUN: %status 1 idris-mlir-opt %s --idr-inline="default-pipeline=no-such-pass" -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: idris-mlir-opt %s --idr-inline="default-pipeline=canonicalize" | FileCheck %s --check-prefix=INLINED
// idr-inline parses the pipeline it runs on each function before inlining
// into it once, and a pipeline that does not parse fails the pass instead
// of running nothing.
// CHECK: error: idr-inline: the default pipeline "no-such-pass" does not parse: {{.*}}no-such-pass
// INLINED-NOT: func.call @leaf

func.func private @leaf(%x: i64) -> i64 {
  return %x : i64
}

func.func @main(%x: i64) -> i64 {
  %r = func.call @leaf(%x) : (i64) -> i64
  return %r : i64
}
