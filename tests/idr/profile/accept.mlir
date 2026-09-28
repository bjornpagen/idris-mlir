// RUN: idris-mlir-opt %s --idr-check-profile -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// Only what would allocate at runtime is rejected. Constants of any size are
// static data; a string that is built and written goes to output; strings
// that already exist may be measured, compared and matched at runtime; an
// Integer that is a constant, or only passed along, allocates nothing; a
// box or closure op whose operands are all constants is static.
// CHECK-LABEL: func.func @Main.main(
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (!idr.erased, i64, !idr.box<@L>) {quantities = ["0", "w", "w"]}
  }
  idr.data @Holder {
    idr.ctor @Hold tag 0 (!idr.big) {quantities = ["w"]}
  }
  func.func private @inc(%x: i64 {idr.quantity = "w"}) -> i64 {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  func.func private @len(%s: !idr.str {idr.quantity = "w"}) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
  func.func private @pass(%b: !idr.big {idr.quantity = "w"}) -> !idr.data<@Holder> {
    %h = idr.con @Holder::@Hold(%b) : (!idr.big) -> !idr.data<@Holder>
    return %h : !idr.data<@Holder>
  }
  func.func private @list() -> !idr.box<@L> {
    %nil = idr.constant #idr.con<@L::@Nil, []> : !idr.box<@L>
    %e = idr.constant #idr.erased : !idr.erased
    %c1 = arith.constant 1 : i64
    %l = idr.con @L::@Cons(%e, %c1, %nil) : (!idr.erased, i64, !idr.box<@L>) -> !idr.box<@L>
    return %l : !idr.box<@L>
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %big = idr.constant #idr.big<"123456789012345678901234567890"> : !idr.big
    %h = func.call @pass(%big) : (!idr.big) -> !idr.data<@Holder>
    %list = idr.constant #idr.con<@L::@Cons, [#idr.erased, 2, #idr.con<@L::@Nil, []>]> : !idr.box<@L>
    %f = idr.constant #idr.closure<@inc, []> : !idr.fn<(i64) -> (i64)>
    %g = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %s = idr.str.from_char %c
    %w2 = idr.io.put_str %s, %w1
    %yes = idr.constant "yes" : !idr.str
    %no = idr.constant "no" : !idr.str
    %n = arith.extui %c : i32 to i64
    %pick = idr.match_lit %n : i64 -> (!idr.str) {
    case 121 {
      idr.yield %yes : !idr.str
    }
    default {
      idr.yield %no : !idr.str
    }
    }
    %m = idr.match_lit %pick : !idr.str -> (i64) {
    case "yes" {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %len = func.call @len(%pick) : (!idr.str) -> i64
      idr.yield %len : i64
    }
    }
    %x = idr.apply %f(%m) : !idr.fn<(i64) -> (i64)>
    %y = idr.apply %g(%x) : !idr.fn<(i64) -> (i64)>
    %w3 = idr.io.put_int signed %y, %w2 : i64
    return %w3 : !idr.world
  }
}
