// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// NEEDS-ACCEPTANCE: the texts of the program verifier's errors (R04) and the ops they are reported at.
// The rules of a whole program, which its idr.program holds: it names its
// root, an idr.func of it of one of the two root types, and its stage, and
// the program's rules run from the program's verifier: the data types it
// holds, and what each stage lets a value hold. A function's visibility is
// no fact of its own: the root is public, every other function private.

// expected-error @+1 {{has root @missing, which is no idr.func of the program}}
idr.program @program root(@missing) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

idr.program @program root(@a) stage(first) {
  // expected-error @+1 {{is the root, so its type must be () -> i64 or (!idr.world) -> (...), not '(i64) -> i64'}}
  idr.func @a(%x: i64) -> i64 {
    return %x : i64
  }
}

// -----

// Both kinds of root.
idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

idr.program @program root(@a) stage(first) {
  idr.func @a(%w: !idr.world) -> (i64, !idr.world) {
    %c = arith.constant 0 : i64
    return %c, %w : i64, !idr.world
  }
}

// -----

// Containment in place is acyclic: a recursive type is held through a box.
!T = !idr.data<"T", plain [@A(!idr.data<"U", plain [@B(!idr.data<"T">)]>)]>
!U = !idr.data<"U", plain [@B(!idr.data<"T", plain [@A(!idr.data<"U">)]>)]>
// expected-error @+1 {{holds the data type "T", which contains itself in place; a recursive type is held through a box}}
idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @b(%t: !T) -> !T {
    return %t : !T
  }
}

// -----

// Every cycle passes through a box.
!T = !idr.data<"T", plain [@A(!idr.data<"U", plain [@B(!idr.box<!idr.data<"L", list [@Nil() nil, @Cons(!idr.data<"T">, !idr.box<!idr.data<"L">>) cons]>>)]>)]>
idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @b(%t: !T) -> !T {
    return %t : !T
  }
}

// -----

// A memo sum is a cell two references share, so it is held only in a box.
!M = !idr.data<"M", memo [@k() label @k, @running() running, @forced(i64) forced]>
// expected-error @+1 {{holds the memo sum "M" in place; a memo sum is held only in a box}}
idr.program @program root(@a) stage(first) {
  idr.func @k() -> i64 {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @b(%m: !M) -> !M {
    return %m : !M
  }
}

// -----

// A data type carries its body wherever it is written, but inside its own
// body: one written by its name alone elsewhere is no type.
idr.program @program root(@a) stage(higher) {
  // expected-error @+1 {{a data type is written without its body only inside its own body}}
  idr.func @b(%f: !idr.fn<() -> (!idr.data<"Nowhere">)>) {
    return
  }
}

// -----

// A body that never returns ends in ub.unreachable, as a match region that
// crashes does: after a match none of whose regions returns, or after a
// crash.
idr.program @program root(@a) stage(first) {
  idr.func @never(%x: i64) -> i64 {
    idr.match_lit %x : i64 -> () {
    case 0 {
      idr.crash "zero"
      ub.unreachable
    }
    default {
      idr.crash "no"
      ub.unreachable
    }
    }
    ub.unreachable
  }
  idr.func @crashes() -> i64 {
    idr.crash "no"
    ub.unreachable
  }
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    %r = idr.call @never(%c) : (i64) -> i64
    return %r : i64
  }
}

// -----

// The stage says what a value may hold, and the program says it, never
// what a function happens to hold. A closure or a suspension exists only
// in the higher stage: idr-defunctionalize makes each a sum.
idr.program @program root(@a) stage(higher) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @apply(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @force(%t: !idr.lazy<i64>) -> i64 {
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
}

// -----

idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.fn<(i64) -> (i64)>', which holds a closure or a suspension in a program past the higher stage, where idr-defunctionalize has made each a sum}}
  idr.func @apply(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
}

// -----

idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.lazy<i64>', which holds a closure or a suspension in a program past the higher stage, where idr-defunctionalize has made each a sum}}
  idr.func @force(%t: !idr.lazy<i64>) -> i64 {
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
}

// -----

// A grade own or excl exists only once idr-rc counts references.
idr.program @program root(@a) stage(first) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.own<!idr.str>', which is graded own or excl in a program before the owned stage, whose grades idr-rc gives}}
  idr.func @keeps(%s: !idr.own<!idr.str>) -> !idr.own<!idr.str> {
    return %s : !idr.own<!idr.str>
  }
}

// -----

// In the owned stage every reference of ours is graded: owned, exclusive,
// or a view, borrowed. A plain one says nothing of who frees it.
idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{binds argument #0 of region #0, of type '!idr.str', which holds references at the plain grade in the owned stage, where a value of ours that holds one is owned, exclusive or borrowed}}
  idr.func @length(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
}

// -----

// A view is borrowed, a reference held is owned, and static data, which no
// count reaches, stays plain; a word holds no reference at all.
idr.program @program root(@a) stage(owned) {
  idr.func @a() -> i64 {
    %s = idr.constant "abc" : !idr.str
    %n = idr.str.length borrow %s
    return %n : i64
  }
  idr.func @length(%s: !idr.q<many, borrow, !idr.str>) -> i64 {
    %n = idr.str.length borrow %s
    return %n : i64
  }
  idr.func @keeps(%s: !idr.own<!idr.str>) -> !idr.own<!idr.str> {
    return %s : !idr.own<!idr.str>
  }
}

// -----

// A lowered program holds upstream's functions: its root names one of
// them, and no idr.func is left.
idr.program @program root(@main) stage(lowered) {
  // expected-error @+1 {{is an idr.func in a lowered program, which holds upstream's functions}}
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

idr.program @program root(@main) stage(lowered) {
  func.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
