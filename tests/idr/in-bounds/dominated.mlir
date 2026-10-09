// RUN: idris-mlir-opt %s --idr-in-bounds | FileCheck %s
// RUN: idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=no-guards=@clear -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-in-bounds --idr-expect=holds=no-guards=@siblings -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=LEFT < %t.err
// A guard runs before every path to a later guard of its kind on the same
// operands when it is earlier in that guard's block, or in a block that
// encloses it: the later one checks what the first already did, and goes.
// One in the other region of a choice ran on another path, and proves
// nothing: both stay. no-guards holds of a function only when no guard of
// any kind is left in it.
// CHECK-LABEL: func.func @sameBlock(
// CHECK-SAME: %[[X:[^:]*]]: i64, %[[Y:[^:]*]]: i64)
// CHECK: %[[G:.*]] = idr.check.nonzero %[[Y]], "division by zero" : i64
// CHECK-NOT: idr.check.nonzero
// CHECK: idr.div signed %[[X]], %[[G]]
// CHECK-NOT: idr.check.nonzero
// CHECK: idr.mod signed %[[X]], %[[Y]]
// CHECK-NOT: idr.check.nonzero
// CHECK: return
// CHECK-LABEL: func.func @enclosing(
// CHECK: idr.check.nonzero
// CHECK: scf.if
// CHECK-NOT: idr.check.nonzero
// CHECK: idr.mod signed
// CHECK-NOT: idr.check.nonzero
// CHECK: return
// CHECK-LABEL: func.func @siblings(
// CHECK: scf.if
// CHECK: idr.check.nonzero
// CHECK: } else {
// CHECK: idr.check.nonzero
// CHECK: return
// CHECK-LABEL: func.func @clear(
// CHECK-NOT: idr.check
// CHECK: return
// LEFT: error: expected no-guards: idr.check.nonzero is left in @siblings
// LEFT: error: expected no-guards: idr.check.nonzero is left in @siblings
func.func @sameBlock(%x: i64, %y: i64) -> (i64, i64) {
  %g = idr.check.nonzero %y, "division by zero" : i64
  %q = idr.div signed %x, %g : i64
  %h = idr.check.nonzero %y, "division by zero" : i64
  %m = idr.mod signed %x, %h : i64
  return %q, %m : i64, i64
}

func.func @enclosing(%b: i1, %x: i64, %y: i64) -> (i64, i64) {
  %g = idr.check.nonzero %y, "division by zero" : i64
  %q = idr.div signed %x, %g : i64
  %r = scf.if %b -> i64 {
    %h = idr.check.nonzero %y, "division by zero" : i64
    %m = idr.mod signed %x, %h : i64
    scf.yield %m : i64
  } else {
    scf.yield %x : i64
  }
  return %q, %r : i64, i64
}

func.func @siblings(%b: i1, %x: i64, %y: i64) -> i64 {
  %r = scf.if %b -> i64 {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.div signed %x, %g : i64
    scf.yield %q : i64
  } else {
    %h = idr.check.nonzero %y, "division by zero" : i64
    %m = idr.mod signed %x, %h : i64
    scf.yield %m : i64
  }
  return %r : i64
}

// Every guard here goes: the divisor is a constant other than 0, and the
// second guard checks what the first did.
func.func @clear(%x: i64) -> (i64, i64) {
  %three = arith.constant 3 : i64
  %g = idr.check.nonzero %three, "division by zero" : i64
  %q = idr.div signed %x, %g : i64
  %h = idr.check.nonzero %three, "division by zero" : i64
  %m = idr.mod signed %x, %h : i64
  return %q, %m : i64, i64
}
