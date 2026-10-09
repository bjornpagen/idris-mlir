// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A consumer moves into the regions of a match only where it then folds or
// canonicalizes against what it meets there. A constructor that holds a
// value beside a field that is not a constant folds against nothing,
// wherever it is built, and a box constructor does not fold into static
// data.

idr.data @List box {
  idr.ctor @Nil ()
  idr.ctor @Cons (i32, !idr.box<@List>)
}

// Three choices, each consed onto the list the one before built, as a
// generator unrolled at compile time conses its characters: each match
// yields its character and each constructor is built once, after it.
// Moving each constructor into the regions of its match would make the
// next one a consumer of a match of lists, and so on: every region would
// get a copy of the rest of the chain, twice the code at each choice.
// CHECK-LABEL: func.func @chain(
// CHECK-NOT: -> (!idr.box<@List>)
// CHECK-COUNT-3: idr.con @List::@Cons
// CHECK-NOT: idr.con
// CHECK: return
func.func @chain(%a: i64, %b: i64, %c: i64, %tail: !idr.box<@List>) -> !idr.box<@List> {
  %x = idr.match_lit %a : i64 -> (i32) {
  case 0 {
    %k = arith.constant 97 : i32
    idr.yield %k : i32
  }
  default {
    %k = arith.constant 99 : i32
    idr.yield %k : i32
  }
  }
  %l1 = idr.con @List::@Cons(%x, %tail) : (i32, !idr.box<@List>) -> !idr.box<@List>
  %y = idr.match_lit %b : i64 -> (i32) {
  case 0 {
    %k = arith.constant 103 : i32
    idr.yield %k : i32
  }
  default {
    %k = arith.constant 116 : i32
    idr.yield %k : i32
  }
  }
  %l2 = idr.con @List::@Cons(%y, %l1) : (i32, !idr.box<@List>) -> !idr.box<@List>
  %z = idr.match_lit %c : i64 -> (i32) {
  case 0 {
    %k = arith.constant 97 : i32
    idr.yield %k : i32
  }
  default {
    %k = arith.constant 116 : i32
    idr.yield %k : i32
  }
  }
  %l3 = idr.con @List::@Cons(%z, %l2) : (i32, !idr.box<@List>) -> !idr.box<@List>
  return %l3 : !idr.box<@List>
}

// A box constructor whose every field is a constant in each region stays
// after the match: folded there it would be static data, which every holder
// shares, so no consumer could take its cell over. One fresh cell is built.
// CHECK-LABEL: func.func @all_constant(
// CHECK: %[[X:.*]] = idr.match_lit %{{.*}} : i64 -> (i32)
// CHECK: idr.con @List::@Cons(%[[X]], %{{.*}})
// CHECK-NOT: #idr.con<@List::@Cons
// CHECK: return
func.func @all_constant(%a: i64) -> !idr.box<@List> {
  %nil = idr.con @List::@Nil() : () -> !idr.box<@List>
  %x = idr.match_lit %a : i64 -> (i32) {
  case 0 {
    %k = arith.constant 97 : i32
    idr.yield %k : i32
  }
  default {
    %k = arith.constant 99 : i32
    idr.yield %k : i32
  }
  }
  %l = idr.con @List::@Cons(%x, %nil) : (i32, !idr.box<@List>) -> !idr.box<@List>
  return %l : !idr.box<@List>
}

// A cell only one region uses moves into it: it is built only on that
// path, and nothing is copied.
// CHECK-LABEL: func.func @one_region(
// CHECK: idr.match_lit
// CHECK-NEXT: case 0 {
// CHECK-NEXT: idr.con @List::@Cons
func.func @one_region(%a: i64, %v: i32, %t: !idr.box<@List>) -> !idr.box<@List> {
  %l = idr.con @List::@Cons(%v, %t) : (i32, !idr.box<@List>) -> !idr.box<@List>
  %r = idr.match_lit %a : i64 -> (!idr.box<@List>) {
  case 0 {
    idr.yield %l : !idr.box<@List>
  }
  default {
    idr.yield %t : !idr.box<@List>
  }
  }
  return %r : !idr.box<@List>
}

// A cell is built where it is used, in each region that does: a copy is one
// op, which nothing follows in.
// CHECK-LABEL: func.func @two_regions(
// CHECK: idr.match_lit
// CHECK-NEXT: case 0 {
// CHECK-NEXT: idr.con @List::@Cons(%{{.*}}, %{{.*}})
// CHECK: default {
// CHECK-NEXT: idr.con @List::@Cons(%{{.*}}, %{{.*}})
func.func @two_regions(%a: i64, %v: i32, %t: !idr.box<@List>) -> !idr.box<@List> {
  %l = idr.con @List::@Cons(%v, %t) : (i32, !idr.box<@List>) -> !idr.box<@List>
  %r = idr.match_lit %a : i64 -> (!idr.box<@List>) {
  case 0 {
    %k = arith.constant 97 : i32
    %m = idr.con @List::@Cons(%k, %l) : (i32, !idr.box<@List>) -> !idr.box<@List>
    idr.yield %m : !idr.box<@List>
  }
  default {
    %k = arith.constant 99 : i32
    %m = idr.con @List::@Cons(%k, %l) : (i32, !idr.box<@List>) -> !idr.box<@List>
    idr.yield %m : !idr.box<@List>
  }
  }
  return %r : !idr.box<@List>
}

// A call that the constant each region yields closes moves into each, where
// compile-time evaluation computes it. One that passes the choice on beside
// an argument that is not constant stays after the match, called once.
func.func private @twice(%x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
  %r = arith.addi %x, %x : i64
  return %r : i64
}
func.func private @both(%x: i64, %y: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
  %r = arith.addi %x, %y : i64
  return %r : i64
}
// CHECK-LABEL: func.func @closed_call(
// CHECK: idr.match_lit
// CHECK-NEXT: case 0 {
// CHECK-NEXT: call @twice
// CHECK: default {
// CHECK-NEXT: call @twice
func.func @closed_call(%a: i64) -> i64 {
  %x = idr.match_lit %a : i64 -> (i64) {
  case 0 {
    %k = arith.constant 1 : i64
    idr.yield %k : i64
  }
  default {
    %k = arith.constant 2 : i64
    idr.yield %k : i64
  }
  }
  %y = func.call @twice(%x) : (i64) -> i64
  return %y : i64
}
// CHECK-LABEL: func.func @open_call(
// CHECK: %[[X:.*]] = idr.match_lit
// CHECK-NOT: call
// CHECK: call @both(%[[X]], %{{.*}})
func.func @open_call(%a: i64, %b: i64) -> i64 {
  %x = idr.match_lit %a : i64 -> (i64) {
  case 0 {
    %k = arith.constant 1 : i64
    idr.yield %k : i64
  }
  default {
    %k = arith.constant 2 : i64
    idr.yield %k : i64
  }
  }
  %y = func.call @both(%x, %b) : (i64, i64) -> i64
  return %y : i64
}
