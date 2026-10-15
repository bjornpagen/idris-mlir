// RUN: idris-mlir-opt %s | FileCheck %s
// RUN: idris-mlir-opt %s | idris-mlir-opt | FileCheck %s
// Under idr.func the ops of the dialect print without its prefix, as
// func.func prints its own: `call`, `return`, `apply`. Only a name of one
// dot loses it, so `idr.str.length` and `idr.lin.enter` keep theirs, and
// only directly in the function's body: a match region is the match's,
// whose ops keep their prefix. The text reads back as itself.
// CHECK-LABEL: idr.func private @prefix(
// CHECK-NEXT: {{^ *}}%clo = closure @inc() : () -> !idr.fn<(i64) -> i64>
// CHECK-NEXT: {{^ *}}%applied = apply %clo(%{{[^)]*}}) : !idr.fn<(i64) -> i64>
// CHECK-NEXT: idr.str.length
// CHECK-NEXT: {{^ *}}%{{[^ ]+}} = match %{{[^ ]+}} : !M -> (i64) {
// CHECK-NEXT: case @Just(%f0: i64) {
// CHECK-NEXT: {{^ *}}%[[INC:.*]] = idr.call @inc(%f0) : (i64) -> i64
// CHECK-NEXT: {{^ *}}%[[JUST:.*]] = idr.con @Just(%[[INC]]) : (i64) -> !M
// CHECK-NEXT: {{^ *}}idr.yield %[[INC]] : i64
// CHECK-NEXT: }
// CHECK-NEXT: default {
// CHECK-NEXT: {{^ *}}idr.yield
// CHECK-NEXT: }
// CHECK-NEXT: }
// CHECK-NEXT: idr.io.put_int signed
// CHECK-NEXT: {{^ *}}%[[OUT:.*]] = call @inc(%applied) : (i64) -> i64
// CHECK-NEXT: {{^ *}}return %[[OUT]], %{{[^ ]+}} : i64, !idr.world

!M = !idr.data<"M", plain [@Nothing(), @Just(i64)]>
idr.func private @inc(%x: i64) -> i64 {
  return %x : i64
}
idr.func private @prefix(%m: !M, %x: i64, %s: !idr.str, %w: !idr.world)
    -> (i64, !idr.world) {
  %c = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
  %a = idr.apply %c(%x) : !idr.fn<(i64) -> (i64)>
  %n = idr.str.length %s
  %r = idr.match %m : !M -> (i64) {
  case @Just(%v: i64) {
    %i = idr.call @inc(%v) : (i64) -> i64
    %k = idr.con @Just(%i) : (i64) -> !M
    idr.yield %i : i64
  }
  default {
    idr.yield %n : i64
  }
  }
  %w1 = idr.io.put_int signed %r, %w : i64
  %t = idr.call @inc(%a) : (i64) -> i64
  return %t, %w1 : i64, !idr.world
}
