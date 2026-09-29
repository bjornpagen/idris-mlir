// RUN: idris-mlir-opt %s --idr-expect=holds=every-cycle-has-breaker -o /dev/null
// RUN: sed 's/attributes {no_inline} //' %s > %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=every-cycle-has-breaker -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// A cycle of calls holds when one of its functions is no_inline, whichever
// it is, and fails, naming the cycle, when none is.
// CHECK: error: expected every-cycle-has-breaker: no loop breaker in the cycle of {{.*}}@{{even|odd}}
// CHECK-NOT: error:
module {
  func.func private @even(%n: i64) -> i64 attributes {no_inline} {
    %r = func.call @odd(%n) : (i64) -> i64
    return %r : i64
  }
  func.func private @odd(%n: i64) -> i64 {
    %r = func.call @even(%n) : (i64) -> i64
    return %r : i64
  }
  func.func private @leaf(%n: i64) -> i64 {
    return %n : i64
  }
}
