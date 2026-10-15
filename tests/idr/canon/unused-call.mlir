// RUN: idris-mlir-opt %s --idr-effects --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s --check-prefix=UNWRITTEN
// RUN: idris-mlir-opt %s --idr-effects --canonicalize=test-convergence=true -o /dev/null
// An unused call goes when its callee is pure, total and cannot crash.
// What a call may do is its own effects, which idr-effects writes from its
// callee's; a call it has not written may do anything, so canonicalize
// alone keeps every call.
// UNWRITTEN-LABEL: idr.func private @main(
// UNWRITTEN: call @square(

idr.func private @square(%x: i64) -> i64 attributes {total} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
idr.func private @partial(%x: i64) -> i64 {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
idr.func private @divides(%x: i64) -> i64 attributes {total} {
  %y = idr.check.nonzero %x, "division by zero" : i64
  %r = idr.div signed %x, %y : i64
  return %r : i64
}
idr.func private @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}

// CHECK-LABEL: idr.func private @main(
// CHECK-SAME: %[[X:.*]]: i64, %[[W:.*]]: !idr.world)
// CHECK-NEXT: call @partial(%[[X]])
// CHECK-NEXT: call @divides(%[[X]])
// CHECK-NEXT: %[[W1:.*]] = call @writes(%[[X]], %[[W]])
// CHECK-NEXT: return %[[W1]]
idr.func private @main(%x: i64, %w: !idr.world) -> !idr.world {
  %a = idr.call @square(%x) : (i64) -> i64
  %b = idr.call @partial(%x) : (i64) -> i64
  %c = idr.call @divides(%x) : (i64) -> i64
  %w1 = idr.call @writes(%x, %w) : (i64, !idr.world) -> !idr.world
  return %w1 : !idr.world
}
