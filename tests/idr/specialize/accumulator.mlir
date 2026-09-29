// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// An accumulator and a counter are never specialized on, static as they
// are: each clone would take the next value, one clone per iteration. The
// call of @count keeps its constants and runs as a loop.
// CHECK-NOT: $spec$
// CHECK-LABEL: func.func private @use(
// CHECK: call @count(%{{.*}}, %{{.*}}) : (i64, !idr.big) -> i64
// CHECK-NOT: $spec$
module attributes {idr.program} {
  func.func private @count(%acc: i64, %n: !idr.big) -> i64 attributes {idr.total} {
    %r = idr.match_lit %n : !idr.big -> (i64) {
    case #idr.big<"0"> {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %one = idr.constant #idr.big<"1"> : !idr.big
      %a = arith.addi %acc, %c1 : i64
      %m = idr.big.sub %n, %one
      %x = func.call @count(%a, %m) : (i64, !idr.big) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @use(%acc: i64) -> i64 attributes {idr.total} {
    %c100 = idr.constant #idr.big<"100"> : !idr.big
    %r = func.call @count(%acc, %c100) : (i64, !idr.big) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
