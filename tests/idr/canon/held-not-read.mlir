// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=grows-nothing=@chain:%s,builds=@all_constant,\
// RUN: builds-where-used=@one_region,builds-where-used=@two_regions,calls-closed=@closed_call:@twice,\
// RUN: grows-nothing=@open_call:%s -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// A consumer moves into the regions of a match only where it then folds or
// canonicalizes against what it meets there. A constructor that holds a
// value beside a field that is not a constant folds against nothing,
// wherever it is built, and a box constructor does not fold into static
// data.

// Three choices, each consed onto the list the one before built, as a
// generator unrolled at compile time conses its characters: each match
// yields its character and each constructor is built once, after it.
// Moving each constructor into the regions of its match would make the
// next one a consumer of a match of lists, and so on: every region would
// get a copy of the rest of the chain, twice the code at each choice. So
// the function grows nothing.
// CHECK-COUNT-3: con {{.*}}@Cons
!List = !idr.data<"List", list [@Nil() nil, @Cons(i32, !idr.box<!idr.data<"List">>) cons]>
idr.program @"held-not-read" root(@root) stage(first) {
  idr.func @chain(%a: i64, %b: i64, %c: i64, %tail: !idr.box<!List>) -> !idr.box<!List> {
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
    %l1 = idr.con !idr.box<!List> @Cons(%x : i32, %tail : !idr.box<!List>)
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
    %l2 = idr.con !idr.box<!List> @Cons(%y : i32, %l1 : !idr.box<!List>)
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
    %l3 = idr.con !idr.box<!List> @Cons(%z : i32, %l2 : !idr.box<!List>)
    return %l3 : !idr.box<!List>
  }

  // A box constructor whose every field is a constant in each region stays
  // after the match: folded there it would be static data, which every holder
  // shares, so no consumer could take its cell over. One fresh cell is built.
  idr.func @all_constant(%a: i64) -> !idr.box<!List> {
    %nil = idr.con !idr.box<!List> @Nil()
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
    %l = idr.con !idr.box<!List> @Cons(%x : i32, %nil : !idr.box<!List>)
    return %l : !idr.box<!List>
  }

  // A cell only one region uses moves into it: it is built only on the
  // path that uses it, and nothing is copied.
  idr.func @one_region(%a: i64, %v: i32, %t: !idr.box<!List>) -> !idr.box<!List> {
    %l = idr.con !idr.box<!List> @Cons(%v : i32, %t : !idr.box<!List>)
    %r = idr.match_lit %a : i64 -> (!idr.box<!List>) {
    case 0 {
      idr.yield %l : !idr.box<!List>
    }
    default {
      idr.yield %t : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }

  // A cell is built where it is used, in each region that does: a copy is one
  // op, which nothing follows in.
  idr.func @two_regions(%a: i64, %v: i32, %t: !idr.box<!List>) -> !idr.box<!List> {
    %l = idr.con !idr.box<!List> @Cons(%v : i32, %t : !idr.box<!List>)
    %r = idr.match_lit %a : i64 -> (!idr.box<!List>) {
    case 0 {
      %k = arith.constant 97 : i32
      %m = idr.con !idr.box<!List> @Cons(%k : i32, %l : !idr.box<!List>)
      idr.yield %m : !idr.box<!List>
    }
    default {
      %k = arith.constant 99 : i32
      %m = idr.con !idr.box<!List> @Cons(%k : i32, %l : !idr.box<!List>)
      idr.yield %m : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }

  // A call that the constant each region yields closes moves into each, where
  // compile-time evaluation computes it: every call of it is closed. One that
  // passes the choice on beside an argument that is not constant stays after
  // the match, called once, so the function grows nothing. A call moves only
  // when its callee's effects say it only computes.
  idr.func @twice(%x: i64) -> i64 attributes {total, effects = #idr.effects<none>} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  idr.func @both(%x: i64, %y: i64) -> i64 attributes {total, effects = #idr.effects<none>} {
    %r = arith.addi %x, %y : i64
    return %r : i64
  }
  idr.func @closed_call(%a: i64) -> i64 {
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
    %y = idr.call @twice(%x) : (i64) -> i64
    return %y : i64
  }
  idr.func @open_call(%a: i64, %b: i64) -> i64 {
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
    %y = idr.call @both(%x, %b) : (i64, i64) -> i64
    return %y : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
