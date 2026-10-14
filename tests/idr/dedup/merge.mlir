// RUN: idris-mlir-opt %s --idr-deduplicate -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-deduplicate -o %t.again.mlir
// RUN: diff %t.mlir %t.again.mlir
// Private functions that are one function twice over become one: @B.inc is
// @A.inc (and the one kept takes its no_inline), @B.id is @A.id, two
// outlines of one body, and @B.down is @A.down though each calls itself
// by its own name. A call, and a closure naming one of them, name the
// one kept, and a second run changes nothing.
// CHECK-NOT: idr.func private @B
// CHECK: idr.func private @A.inc(
// CHECK-SAME: no_inline
// CHECK: idr.func private @A.id(
// CHECK: idr.func private @A.down(
// CHECK: idr.func @root(
// CHECK: call @A.inc(
// CHECK: call @A.inc(
// CHECK: closure @A.inc(
// CHECK: call @A.down(
// CHECK: call @A.down(
module {
  idr.func private @A.inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func private @B.inc(%x: i64) -> i64 attributes {no_inline, total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func private @A.id(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func private @B.id(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func private @A.down(%n: i64, %acc: i64) -> i64 attributes {total} {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %s = arith.addi %acc, %n : i64
      %t = idr.call @A.down(%m, %s) : (i64, i64) -> i64
      idr.yield %t : i64
    }
    }
    return %r : i64
  }
  idr.func private @B.down(%n: i64, %acc: i64) -> i64 attributes {total} {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %s = arith.addi %acc, %n : i64
      %t = idr.call @B.down(%m, %s) : (i64, i64) -> i64
      idr.yield %t : i64
    }
    }
    return %r : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 7 : i64
    %z = arith.constant 0 : i64
    %a = idr.call @A.inc(%n) : (i64) -> i64
    %b = idr.call @B.inc(%a) : (i64) -> i64
    %f = idr.closure @B.inc() : () -> !idr.fn<(i64) -> (i64)>
    %c = idr.apply %f(%b) : !idr.fn<(i64) -> (i64)>
    %d = idr.call @B.id(%c) : (i64) -> i64
    %e = idr.call @A.down(%d, %z) : (i64, i64) -> i64
    %r = idr.call @B.down(%e, %z) : (i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w : i64
    return %w2 : !idr.world
  }
}
