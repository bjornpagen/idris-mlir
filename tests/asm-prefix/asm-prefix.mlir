// RUN: idris-mlir-opt %s | FileCheck %s
// RUN: idris-mlir-opt %s | idris-mlir-opt | FileCheck %s
// Under idr.func the ops of the dialect print without its prefix, as
// func.func prints its own: `call`, `return`, `apply`. Only a name of one
// dot loses it, so `idr.str.length` and `idr.lin.enter` keep theirs, and
// only directly in the function's body: a match region is the match's,
// whose ops keep their prefix. The text reads back as itself.
// CHECK-LABEL: idr.func @prefix(
// CHECK: {{^ *}}%{{[^ ]+}} = closure @inc(
// CHECK: {{^ *}}%{{[^ ]+}} = apply %
// CHECK: {{^ *}}%{{[^ ]+}} = idr.str.length %
// CHECK: {{^ *}}%{{[^ ]+}} = match %
// CHECK: {{^ *}}%{{[^ ]+}} = idr.call @inc(
// CHECK: {{^ *}}%{{[^ ]+}} = idr.con !M @Just
// CHECK: {{^ *}}idr.yield %
// CHECK: {{^ *}}idr.yield %
// CHECK: {{^ *}}%{{[^ ]+}} = idr.io.put_sint %
// CHECK: {{^ *}}%{{[^ ]+}} = call @inc(
// CHECK: {{^ *}}return %

!M = !idr.data<"M", plain [@Nothing(), @Just(i64)]>
idr.program @prefix root(@root) stage(higher) {
  idr.func @inc(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @prefix(%m: !M, %x: i64, %s: !idr.str, %w: !idr.world)
      -> (i64, !idr.world) {
    %c = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %a = idr.apply %c(%x) : !idr.fn<(i64) -> (i64)>
    %n = idr.str.length %s
    %r = idr.match %m : !M -> (i64) {
    case @Just(%v: i64) {
      %i = idr.call @inc(%v) : (i64) -> i64
      %k = idr.con !M @Just(%i : i64)
      idr.yield %i : i64
    }
    default(%d: !M) {
      idr.yield %n : i64
    }
    }
    %w1 = idr.io.put_sint %r, %w : i64
    %t = idr.call @inc(%a) : (i64) -> i64
    return %t, %w1 : i64, !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
