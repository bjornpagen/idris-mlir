// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// NEEDS-ACCEPTANCE: the texts and places of the root's errors and of the bodiless function's are C03's; check each against it.
// The rules of a whole program. Its root is its one public function, of
// one of the two root types, and the module's rules run from the root's
// verifier, so they hold on every module with a root and need no mark. A
// module with no public function is a fragment and gets each function's
// rules only. Every function has a body: the world is closed.

// expected-error @+1 {{expects exactly one public function (the root), found 2}}
module {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @b() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// A fragment: no root, so only each function's rules.
module {
  idr.func private @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

module {
  // expected-error @+1 {{is the root, so its type must be () -> i64 or (!idr.world) -> (...), not '(i64) -> i64'}}
  idr.func @a(%x: i64) -> i64 {
    return %x : i64
  }
}

// -----

module {
  // expected-error @+1 {{expects a body}}
  idr.func private @a(i64) -> i64
}

// -----

// Both kinds of root.
module {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

module {
  idr.func @a(%w: !idr.world) -> (i64, !idr.world) {
    %c = arith.constant 0 : i64
    return %c, %w : i64, !idr.world
  }
}

// -----

// Containment in place is acyclic: a recursive type is held through a box.
!T = !idr.data<"T", plain [@A(!idr.data<"U", plain [@B(!idr.data<"T">)]>)]>
!U = !idr.data<"U", plain [@B(!idr.data<"T", plain [@A(!idr.data<"U">)]>)]>
// expected-error @+1 {{the data type "T" contains itself in place; a recursive type is held through a box}}
module {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func private @b(%t: !T) -> !T {
    return %t : !T
  }
}

// -----

// Every cycle passes through a box.
!T = !idr.data<"T", plain [@A(!idr.data<"U", plain [@B(!idr.box<!idr.data<"L", list [@Nil(), @Cons(!idr.data<"T">, !idr.box<!idr.data<"L">>)]>>)]>)]>
module {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func private @b(%t: !T) -> !T {
    return %t : !T
  }
}

// -----

// A memo sum is a cell two references share, so it is held only in a box.
!M = !idr.data<"M", memo [@running(), @forced(i64)]>
module {
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  // expected-error @+1 {{holds the memo sum "M" in place; a memo sum is held only in a box}}
  idr.func private @b(%m: !M) -> !M {
    return %m : !M
  }
}

// -----

// A data type carries its body wherever it is written, but inside its own
// body: one written by its name alone elsewhere is no type.
module {
  // expected-error @+1 {{a data type is written without its body only inside its own body}}
  idr.func private @b(%f: !idr.fn<() -> (!idr.data<"Nowhere">)>) {
    return
  }
}

// -----

// A body that never returns ends in ub.unreachable, as a match region that
// crashes does: after a match none of whose regions returns, or after a
// crash.
module {
  idr.func private @never(%x: i64) -> i64 {
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
  idr.func private @crashes() -> i64 {
    idr.crash "no"
    ub.unreachable
  }
  idr.func @a() -> i64 {
    %c = arith.constant 0 : i64
    %r = idr.call @never(%c) : (i64) -> i64
    return %r : i64
  }
}
