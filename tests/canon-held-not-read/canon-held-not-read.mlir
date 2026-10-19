// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=grows-nothing=@chain:%s,builds=@all_constant,\
// RUN: builds-where-used=@one_region,builds-where-used=@two_regions,calls-closed=@closed_call:@twice,\
// RUN: grows-nothing=@open_call:%s -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=builds-where-used=@one_region,builds-where-used=@two_regions,calls-closed=@closed_call:@twice' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=calls-closed=@open_call:@both' -o /dev/null
// RUN: awk '/^  idr.func @chain/ { inside = 1 } inside && /^    %l3 = / { printf "    %%unused = arith.addi %%a, %%b : i64\n"; inside = 0 } { print }' %s > %t.grown.mlir
// RUN: %status 1 idris-mlir-opt %t.grown.mlir --idr-expect=holds=grows-nothing=@chain:%s -o /dev/null
// BEFORE-DAG: expected builds-where-used: {{.*}}@one_region
// BEFORE-DAG: expected builds-where-used: {{.*}}@two_regions
// BEFORE-DAG: expected calls-closed: {{.*}}@twice in @closed_call
// A consumer moves into the regions of a match only where it then folds or
// canonicalizes against what it meets there. A constructor that holds a
// value beside a field that is not a constant folds against nothing,
// wherever it is built, and a box constructor does not fold into static
// data.
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it; a call of @both that takes a value is
// not closed, and a copy of @chain with one more op than the file's grows.

// Three choices, each consed onto the list the one before built, as a
// generator unrolled at compile time conses its characters: each match
// yields its character and each constructor is built once, after it.
// Moving each constructor into the regions of its match would make the
// next one a consumer of a match of lists, and so on: every region would
// get a copy of the rest of the chain, twice the code at each choice. So
// the function grows nothing.
!List = !idr.data<"List", list [@Nil() nil, @Cons(i32, !idr.box<!idr.data<"List">>) cons]>
idr.program @"held-not-read" root(@root) stage(first) {
  idr.func @chain(%a: i64, %b: i64, %c: i64, %tail: !idr.box<!List>) -> !idr.box<!List> {
    %x = idr.match_lit %a : i64 -> (i32) {
    case 0 {
      %k = arith.constant 97 : i32
      idr.yield %k : i32
    }
    default(%d: i64) {
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
    default(%d1: i64) {
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
    default(%d2: i64) {
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
    default(%d: i64) {
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
    default(%d: i64) {
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
    default(%d: i64) {
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
  // when its own effects say it only computes.
  idr.func effects<none> @twice(%x: i64) -> i64 attributes {total} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  idr.func effects<none> @both(%x: i64, %y: i64) -> i64 attributes {total} {
    %r = arith.addi %x, %y : i64
    return %r : i64
  }
  idr.func @closed_call(%a: i64) -> i64 {
    %x = idr.match_lit %a : i64 -> (i64) {
    case 0 {
      %k = arith.constant 1 : i64
      idr.yield %k : i64
    }
    default(%d: i64) {
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
    default(%d: i64) {
      %k = arith.constant 2 : i64
      idr.yield %k : i64
    }
    }
    %y = idr.call @both(%x, %b) : (i64, i64) -> i64
    return %y : i64
  }
  // Writes the characters of a list.
  idr.func @put_chars(%l: !idr.box<!List>, %w: !idr.world) -> !idr.world {
    %r = idr.match %l : !idr.box<!List> -> (!idr.world) {
    case @Nil() {
      idr.yield %w : !idr.world
    }
    case @Cons(%c: i32, %t: !idr.box<!List>) {
      %w1 = idr.io.put_char %c, %w
      %w2 = idr.call @put_chars(%t, %w1) : (!idr.box<!List>, !idr.world) -> !idr.world
      idr.yield %w2 : !idr.world
    }
    }
    return %r : !idr.world
  }
  // The program's root runs every function above on what it reads: each
  // choice is a bit of the byte, and the rest of it a number.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %c4 = arith.constant 4 : i64
    %c8 = arith.constant 8 : i64
    %a = arith.andi %byte, %c1 : i64
    %b1 = arith.andi %byte, %c2 : i64
    %c3 = arith.andi %byte, %c4 : i64
    %rest = arith.shrui %byte, %c8 : i64
    %nil = idr.con !idr.box<!List> @Nil()
    %bang = arith.constant 33 : i32
    %tail = idr.con !idr.box<!List> @Cons(%bang : i32, %nil : !idr.box<!List>)
    %l0 = idr.call @chain(%a, %b1, %c3, %tail) : (i64, i64, i64, !idr.box<!List>) -> !idr.box<!List>
    %w1 = idr.call @put_chars(%l0, %w0) : (!idr.box<!List>, !idr.world) -> !idr.world
    %l1 = idr.call @all_constant(%b1) : (i64) -> !idr.box<!List>
    %w2 = idr.call @put_chars(%l1, %w1) : (!idr.box<!List>, !idr.world) -> !idr.world
    %l2 = idr.call @one_region(%a, %ch, %tail) : (i64, i32, !idr.box<!List>) -> !idr.box<!List>
    %w3 = idr.call @put_chars(%l2, %w2) : (!idr.box<!List>, !idr.world) -> !idr.world
    %l3 = idr.call @two_regions(%c3, %ch, %tail) : (i64, i32, !idr.box<!List>) -> !idr.box<!List>
    %w4 = idr.call @put_chars(%l3, %w3) : (!idr.box<!List>, !idr.world) -> !idr.world
    %r0 = idr.call @closed_call(%b1) : (i64) -> i64
    %w5 = idr.io.put_sint %r0, %w4 : i64
    %r1 = idr.call @open_call(%a, %byte) : (i64, i64) -> i64
    %w6 = idr.io.put_sint %r1, %w5 : i64
    return %w6 : !idr.world
  }
}
