// RUN: idris-mlir-opt %s --idr-returned-arguments --canonicalize | FileCheck %s
// A result that is one argument on every path, here through the join of an
// scf.if and through the recursive call that gives the argument back, is
// dropped: the function returns the rest, and its callers use the argument
// they passed (find's array, sometimes' count). So is the argument a loop
// carries unchanged and gives back on its exit paths, with poison where it
// continues (the shape idr-tail-loops leaves). A result that is an argument
// on one path only stays (sometimes' pointer), and so does every result of
// a public function and of one a func.constant names. The join then yields
// the same value on each path for the dropped result, which canonicalize
// folds (and it makes the call through the constant a direct one).
// CHECK-LABEL: func.func @root(
// CHECK-SAME: %[[P:[^:]*]]: !llvm.ptr, %[[M:[^:]*]]: i64) -> (!llvm.ptr, i64)
// CHECK: %[[V:.*]] = call @find(%[[P]], %[[M]], %[[M]]) : (!llvm.ptr, i64, i64) -> i64
// CHECK: %[[W:.*]] = call @sometimes(%[[P]], %[[P]], %[[M]]) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
// CHECK: %[[X:.*]]:2 = call @named(%[[W]], %[[M]]) : (!llvm.ptr, i64) -> (i64, !llvm.ptr)
// CHECK: %[[Y:.*]]:2 = call @named(%[[X]]#1, %[[M]]) : (!llvm.ptr, i64) -> (i64, !llvm.ptr)
// CHECK: %[[Z:.*]] = call @loop(%[[Y]]#1, %[[M]]) : (!llvm.ptr, i64) -> i64
// CHECK: return %[[Y]]#1, %[[Z]]
// CHECK-LABEL: func.func private @find(
// CHECK-SAME: %[[A:[^:]*]]: !llvm.ptr, %[[N:[^:]*]]: i64, %[[I:[^:]*]]: i64) -> i64
// CHECK: %[[R:.*]] = scf.if %{{.*}} -> (i64) {
// CHECK: %[[K:.*]] = arith.addi %[[N]], %[[I]] : i64
// CHECK: scf.yield %[[K]] : i64
// CHECK: %[[S:.*]] = func.call @find(%[[A]], %[[N]], %{{.*}}) : (!llvm.ptr, i64, i64) -> i64
// CHECK: scf.yield %[[S]] : i64
// CHECK: return %[[R]] : i64
// CHECK-LABEL: func.func private @sometimes(
// CHECK-SAME: -> !llvm.ptr
// CHECK-LABEL: func.func private @loop(
// CHECK-SAME: -> i64
// CHECK-LABEL: func.func private @named(
// CHECK-SAME: -> (i64, !llvm.ptr)
module {
  func.func @root(%p: !llvm.ptr, %m: i64) -> (!llvm.ptr, i64) {
    %v, %q = func.call @find(%p, %m, %m) : (!llvm.ptr, i64, i64) -> (i64, !llvm.ptr)
    %w, %r = func.call @sometimes(%q, %q, %m) : (!llvm.ptr, !llvm.ptr, i64) -> (i64, !llvm.ptr)
    %x, %s = func.call @named(%r, %w) : (!llvm.ptr, i64) -> (i64, !llvm.ptr)
    %f = func.constant @named : (!llvm.ptr, i64) -> (i64, !llvm.ptr)
    %y, %t = func.call_indirect %f(%s, %w) : (!llvm.ptr, i64) -> (i64, !llvm.ptr)
    %z, %u = func.call @loop(%t, %m) : (!llvm.ptr, i64) -> (i64, !llvm.ptr)
    return %u, %z : !llvm.ptr, i64
  }
  // The first argument comes back on every path; the count does not.
  func.func private @find(%a: !llvm.ptr, %n: i64, %i: i64) -> (i64, !llvm.ptr) {
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %done = arith.cmpi eq, %i, %c0 : i64
    %r, %b = scf.if %done -> (i64, !llvm.ptr) {
      %k = arith.addi %n, %i : i64
      scf.yield %k, %a : i64, !llvm.ptr
    } else {
      %j = arith.subi %i, %c1 : i64
      %s, %c = func.call @find(%a, %n, %j) : (!llvm.ptr, i64, i64) -> (i64, !llvm.ptr)
      scf.yield %s, %c : i64, !llvm.ptr
    }
    return %r, %b : i64, !llvm.ptr
  }
  // The count comes back; the pointer is one argument on one path and
  // another on the other.
  func.func private @sometimes(%a: !llvm.ptr, %b: !llvm.ptr, %n: i64) -> (i64, !llvm.ptr) {
    %c0 = arith.constant 0 : i64
    %zero = arith.cmpi eq, %n, %c0 : i64
    %r = scf.if %zero -> (!llvm.ptr) {
      scf.yield %a : !llvm.ptr
    } else {
      scf.yield %b : !llvm.ptr
    }
    return %n, %r : i64, !llvm.ptr
  }
  // Counts down; the pointer is loop state every iteration yields unchanged,
  // and the loop's exit value where it stops, poison where it goes on.
  func.func private @loop(%a: !llvm.ptr, %n: i64) -> (i64, !llvm.ptr) {
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %c7 = arith.constant 7 : i64
    %r:4 = scf.while (%s = %a, %i = %n) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64, !llvm.ptr) {
      %done = arith.cmpi eq, %i, %c0 : i64
      %p = ub.poison : !llvm.ptr
      %q = ub.poison : i64
      %next:4 = scf.if %done -> (i1, i64, i64, !llvm.ptr) {
        %false = arith.constant false
        %k = arith.addi %n, %c7 : i64
        scf.yield %false, %q, %k, %s : i1, i64, i64, !llvm.ptr
      } else {
        %true = arith.constant true
        %j = arith.subi %i, %c1 : i64
        scf.yield %true, %j, %q, %p : i1, i64, i64, !llvm.ptr
      }
      scf.condition(%next#0) %s, %next#1, %next#2, %next#3 : !llvm.ptr, i64, i64, !llvm.ptr
    } do {
    ^bb0(%s2: !llvm.ptr, %i2: i64, %v: i64, %out: !llvm.ptr):
      scf.yield %s2, %i2 : !llvm.ptr, i64
    }
    return %r#2, %r#3 : i64, !llvm.ptr
  }
  // Gives its argument back, but a func.constant names it: its type stays.
  func.func private @named(%a: !llvm.ptr, %n: i64) -> (i64, !llvm.ptr) {
    return %n, %a : i64, !llvm.ptr
  }
}
