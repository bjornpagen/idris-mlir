// RUN: idris-mlir-opt %s --idr-isolate | FileCheck %s
// An evaluated suspension of a plain value stays a delay, and one of a
// closure is outlined to a suspension like a body that computes: as a
// label of its cell the analysis of labels sees the closure it holds,
// where a cell already forced would hold it in a slot no key follows.
// CHECK-LABEL: idr.func @Main.main(
// CHECK: %[[F:.*]] = closure @inc() : () -> !idr.fn<(i64) -> i64>
// CHECK: suspend @Main.main.delay{{[0-9]+}}(%[[F]]) : (!idr.fn<(i64) -> i64>) -> !idr.lazy<!idr.fn<(i64) -> i64>>
// CHECK: %[[T:.*]] = {{(idr\.)?}}delay : !idr.lazy<i64> {
// CHECK-NEXT: idr.yield %{{.*}} : i64
module attributes {idr.program} {
  idr.func private @inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> i64>
    %held = idr.delay : !idr.lazy<!idr.fn<(i64) -> i64>> {
      idr.yield %f : !idr.fn<(i64) -> i64>
    }
    %plain = idr.delay : !idr.lazy<i64> {
      idr.yield %n : i64
    }
    %g = idr.force %held : !idr.lazy<!idr.fn<(i64) -> i64>> -> !idr.fn<(i64) -> i64>
    %v = idr.force %plain : !idr.lazy<i64> -> i64
    %r = idr.apply %g(%v) : !idr.fn<(i64) -> i64>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
