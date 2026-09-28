// RUN: idris-mlir-opt %s --mlir-disable-threading --idr-eval --remarks-filter=idr-eval 2> %t.remarks | FileCheck %s
// RUN: FileCheck %s --check-prefix=REMARK < %t.remarks
// rule: EVAL-1, SEM-EVAL-6, LOW-JIT-1, IDR-CONST-1
// Each closed call of a pure, total function runs, lowered as executables
// are, and its results come back as constants of every kind: scalars,
// strings, bigs of both sizes, unboxed and boxed constructors, closures with
// their captures, and the erased value. An application of a constant
// closure is a closed call of its function with the captures first.
// CHECK-LABEL: func.func @Prog.main()
// CHECK-NOT: call
// CHECK-DAG: arith.constant 3628800 : i64
// CHECK-DAG: arith.constant -1 : i8
// CHECK-DAG: arith.constant 0x7FF8000000000000 : f64
// CHECK-DAG: idr.constant "h\C3\A9h\C3\A9" : !idr.str
// CHECK-DAG: idr.constant #idr.big<"-7"> : !idr.big
// CHECK-DAG: idr.constant #idr.big<"2432902008176640000"> : !idr.big
// CHECK-DAG: idr.constant #idr.con<@Shape::@Rect, [2.500000e+00, #idr.erased, "tall"]> : !idr.data<@Shape>
// CHECK-DAG: idr.constant #idr.con<@List::@Cons, [3, #idr.con<@List::@Cons, [2, #idr.con<@List::@Cons, [1, #idr.con<@List::@Nil, []>]>]>]> : !idr.box<@List>
// CHECK-DAG: idr.constant #idr.closure<@addTo, [#idr.big<"5">, #idr.con<@Shape::@Dot, []>]> : !idr.fn<(i64) -> (i64)>
// CHECK-DAG: arith.constant 47 : i64
// CHECK: return
// REMARK-COUNT-10: remark: [Passed] Evaluated | Category:idr-eval
// REMARK-NOT: remark:
module {
  idr.data @List box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.box<@List>) {quantities = ["w", "w"]}
  }
  idr.data @Shape {
    idr.ctor @Dot tag 0 () {quantities = []}
    idr.ctor @Rect tag 1 (f64, !idr.erased, !idr.str) {quantities = ["w", "0", "w"]}
  }
  func.func private @fact(%n: i64) -> i64 attributes {idr.total, idr.effect = "pure"} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f = func.call @fact(%m) : (i64) -> i64
      %p = arith.muli %n, %f : i64
      idr.yield %p : i64
    }
    }
    return %r : i64
  }
  func.func private @bigFact(%n: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.match_lit %n : !idr.big -> (!idr.big) {
    case #idr.big<"0"> {
      %one = idr.constant #idr.big<"1"> : !idr.big
      idr.yield %one : !idr.big
    }
    default {
      %one = idr.constant #idr.big<"1"> : !idr.big
      %m = idr.big.sub %n, %one
      %f = func.call @bigFact(%m) : (!idr.big) -> !idr.big
      %p = idr.big.mul %n, %f
      idr.yield %p : !idr.big
    }
    }
    return %r : !idr.big
  }
  func.func private @narrow(%n: i64) -> i8 attributes {idr.total, idr.effect = "pure"} {
    %r = arith.trunci %n : i64 to i8
    return %r : i8
  }
  func.func private @nan(%x: f64) -> f64 attributes {idr.total, idr.effect = "pure"} {
    %r = arith.divf %x, %x : f64
    return %r : f64
  }
  func.func private @twice(%s: !idr.str) -> !idr.str attributes {idr.total, idr.effect = "pure"} {
    %r = idr.str.append %s, %s
    return %r : !idr.str
  }
  func.func private @negate(%b: !idr.big) -> !idr.big attributes {idr.total, idr.effect = "pure"} {
    %r = idr.big.neg %b
    return %r : !idr.big
  }
  func.func private @rect(%w: f64, %e: !idr.erased, %s: !idr.str) -> !idr.data<@Shape>
      attributes {idr.total, idr.effect = "pure"} {
    %r = idr.con @Shape::@Rect(%w, %e, %s) : (f64, !idr.erased, !idr.str) -> !idr.data<@Shape>
    return %r : !idr.data<@Shape>
  }
  func.func private @range(%n: i64) -> !idr.box<@List> attributes {idr.total, idr.effect = "pure"} {
    %r = idr.match_lit %n : i64 -> (!idr.box<@List>) {
    case 0 {
      %nil = idr.con @List::@Nil() : () -> !idr.box<@List>
      idr.yield %nil : !idr.box<@List>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %rest = func.call @range(%m) : (i64) -> !idr.box<@List>
      %c = idr.con @List::@Cons(%n, %rest) : (i64, !idr.box<@List>) -> !idr.box<@List>
      idr.yield %c : !idr.box<@List>
    }
    }
    return %r : !idr.box<@List>
  }
  func.func private @addTo(%k: !idr.big, %s: !idr.data<@Shape>, %x: i64) -> i64
      attributes {idr.total, idr.effect = "pure"} {
    %i = idr.big.to_int %k : i64
    %r = arith.addi %i, %x : i64
    return %r : i64
  }
  func.func private @adder(%k: !idr.big, %s: !idr.data<@Shape>) -> !idr.fn<(i64) -> (i64)>
      attributes {idr.total, idr.effect = "pure"} {
    %c = idr.closure @addTo(%k, %s) : (!idr.big, !idr.data<@Shape>) -> !idr.fn<(i64) -> (i64)>
    return %c : !idr.fn<(i64) -> (i64)>
  }
  func.func @Prog.main() -> (i64, i8, f64, !idr.str, !idr.big, !idr.big, !idr.data<@Shape>,
                             !idr.box<@List>, !idr.fn<(i64) -> (i64)>, i64) {
    %ten = arith.constant 10 : i64
    %f = func.call @fact(%ten) : (i64) -> i64
    %m = arith.constant 255 : i64
    %b = func.call @narrow(%m) : (i64) -> i8
    %z = arith.constant 0.0 : f64
    %n = func.call @nan(%z) : (f64) -> f64
    %s = idr.constant "h\C3\A9" : !idr.str
    %t = func.call @twice(%s) : (!idr.str) -> !idr.str
    %seven = idr.constant #idr.big<"7"> : !idr.big
    %neg = func.call @negate(%seven) : (!idr.big) -> !idr.big
    %twenty = idr.constant #idr.big<"20"> : !idr.big
    %bf = func.call @bigFact(%twenty) : (!idr.big) -> !idr.big
    %w = arith.constant 2.5 : f64
    %e = idr.constant #idr.erased : !idr.erased
    %tall = idr.constant "tall" : !idr.str
    %r = func.call @rect(%w, %e, %tall) : (f64, !idr.erased, !idr.str) -> !idr.data<@Shape>
    %three = arith.constant 3 : i64
    %l = func.call @range(%three) : (i64) -> !idr.box<@List>
    %five = idr.constant #idr.big<"5"> : !idr.big
    %dot = idr.constant #idr.con<@Shape::@Dot, []> : !idr.data<@Shape>
    %c = func.call @adder(%five, %dot) : (!idr.big, !idr.data<@Shape>) -> !idr.fn<(i64) -> (i64)>
    %k = idr.constant #idr.closure<@addTo, [#idr.big<"5">, #idr.con<@Shape::@Dot, []>]> : !idr.fn<(i64) -> (i64)>
    %fortytwo = arith.constant 42 : i64
    %a = idr.apply %k(%fortytwo) : !idr.fn<(i64) -> (i64)>
    return %f, %b, %n, %t, %neg, %bf, %r, %l, %c, %a
        : i64, i8, f64, !idr.str, !idr.big, !idr.big, !idr.data<@Shape>, !idr.box<@List>,
          !idr.fn<(i64) -> (i64)>, i64
  }
}
