// NEEDS-ACCEPTANCE: that skipping every idr-deduplicate-merge action leaves the module as idr-deduplicate received it, and that idr-deduplicate changes it otherwise.
// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --idr-deduplicate --mlir-disable-threading -mlir-debug-counter=idr-deduplicate-merge-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --idr-deduplicate -o %t.done.mlir
// RUN: not diff %t.none.mlir %t.done.mlir
idr.program @merge root(@root) stage(higher) {
  idr.func @A.inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func @B.inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func @A.twice(%x: i64) -> i64 attributes {total} {
    %y = idr.call @A.inc(%x) : (i64) -> i64
    %z = idr.call @A.inc(%y) : (i64) -> i64
    return %z : i64
  }
  idr.func @B.twice(%x: i64) -> i64 attributes {total} {
    %y = idr.call @B.inc(%x) : (i64) -> i64
    %z = idr.call @B.inc(%y) : (i64) -> i64
    return %z : i64
  }
  idr.func @A.id(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @B.id(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @A.down(%n: i64, %acc: i64) -> i64 attributes {total} {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default(%d0: i1) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %s = arith.addi %acc, %n : i64
      %t = idr.call @A.down(%m, %s) : (i64, i64) -> i64
      idr.yield %t : i64
    }
    }
    return %r : i64
  }
  idr.func @B.down(%n: i64, %acc: i64) -> i64 attributes {total} {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default(%d1: i1) {
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
    %r0 = idr.call @B.down(%e, %z) : (i64, i64) -> i64
    %r1 = idr.call @A.twice(%r0) : (i64) -> i64
    %r = idr.call @B.twice(%r1) : (i64) -> i64
    %w2 = idr.io.put_sint %r, %w : i64
    return %w2 : !idr.world
  }
}
