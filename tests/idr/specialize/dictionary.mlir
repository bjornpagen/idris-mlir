// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=one-clone=@sumTo,not-called=@plus -o /dev/null
// RUN: FileCheck %s --implicit-check-not='call @sumTo(' < %t.mlir
// NEEDS-ACCEPTANCE: that @sumTo is specialized on the whole record and @plus inlined into the copy, as C09 and C08 decide.
// An interface dictionary: a record of closures without captures, built at
// the call. After defunctionalization each closure is a constructor of its
// sum, so the record is entirely static. @sumTo loops, so it is never
// inlined, and it is specialized on the whole record: the copy's field
// read and dispatch fold to a direct call of the implementation, which it
// inlines. No call of @plus is left, @sumTo itself is no longer called,
// and every call made from it reaches the one copy.
// CHECK: idr.func @Main.main(
!Num = !idr.data<"Num", plain [@MkNum(!idr.fn<(i64, i64) -> (i64)>, !idr.fn<(i64) -> (i64)>)]>
module {
  idr.func private @plus(%a: i64, %b: i64) -> i64 attributes {total} {
    %c = arith.addi %a, %b : i64
    return %c : i64
  }
  idr.func private @neg(%a: i64) -> i64 attributes {total} {
    %z = arith.constant 0 : i64
    %c = arith.subi %z, %a : i64
    return %c : i64
  }
  idr.func private @sumTo(%d: !Num, %n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %plus = idr.field %d[@MkNum, 0] : !Num -> !idr.fn<(i64, i64) -> (i64)>
      %a = idr.apply %plus(%acc, %n) : !idr.fn<(i64, i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @sumTo(%d, %m, %a) : (!Num, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  } loc("sumTo")
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %p = idr.closure @plus() : () -> !idr.fn<(i64, i64) -> (i64)>
    %n = idr.closure @neg() : () -> !idr.fn<(i64) -> (i64)>
    %d = idr.con @MkNum(%p, %n) : (!idr.fn<(i64, i64) -> (i64)>, !idr.fn<(i64) -> (i64)>) -> !Num
    %z = arith.constant 0 : i64
    %r = idr.call @sumTo(%d, %x, %z) : (!Num, i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
