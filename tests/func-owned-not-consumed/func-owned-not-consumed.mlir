// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// The owned stage is what a function's grades say: a function with an owned
// value is in it, and idr.func's verifier keeps the stage's rule there,
// with no attribute to say so and no look at the rest of the module. A
// function whose owned value is never consumed is refused; another in the
// same module, which holds no owned value, builds a plain constructor and
// is not asked. The rule is that each reference is consumed exactly once on
// every path: once is no error (the same function, dropping its value);
// twice is, at the second consumer; and so is once on one path of a match
// and not on the other, at the match.

!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@MkP(i64, i64)]
>
idr.program @"owned-not-consumed" root(@root) stage(owned) types #types {
  // expected-note @+1 {{the value is defined here}}
  idr.func @leak(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length borrow %v
    // expected-error @+1 {{returns while a value still holds a reference}}
    return %n : i64
  }
  idr.func @pair(%x: i64) -> !P {
    %p = idr.con !P @MkP(%x : i64, %x : i64)
    return %p : !P
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!L = !idr.data<"L">
#types = #idr.types<
  "L" = list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]
>
idr.program @"owned-not-consumed" root(@root) stage(owned) types #types {
  idr.func @bump(%l: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (!idr.own<!idr.box<!L>>) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      %one = arith.constant 1 : i64
      %h2 = arith.addi %w#1, %one : i64
      %oc = idr.cell.recycle %w#0 : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
      %o = idr.cell.init %oc : !idr.cell<!idr.box<!L>, @C> (%h2 : i64, %w#2 : !idr.own<!idr.box<!L>>)
      idr.yield %o : !idr.own<!idr.box<!L>>
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.yield %l : !idr.own<!idr.box<!L>>
    }
    }
    return %r : !idr.own<!idr.box<!L>>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"owned-not-consumed" root(@root) stage(owned) types #idr.types<> {
  idr.func @consumed(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length borrow %v
    idr.drop %s : !idr.own<!idr.str>
    return %n : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"owned-not-consumed" root(@root) stage(owned) types #idr.types<> {
  // expected-note @+1 {{the value is defined here}}
  idr.func @twice(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length borrow %v
    idr.drop %s : !idr.own<!idr.str>
    // expected-error @+1 {{consumes a reference that the value does not hold here: it was consumed before on this path}}
    idr.drop %s : !idr.own<!idr.str>
    return %n : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"owned-not-consumed" root(@root) stage(owned) types #idr.types<> {
  // expected-note @+1 {{the value is defined here}}
  idr.func @one_path(%b: i1, %s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length borrow %v
    // expected-error @+1 {{leaves a value with 0 references on one path and 1 on another}}
    %r = idr.match_lit %b : i1 -> (i64) {
    case true {
      idr.drop %s : !idr.own<!idr.str>
      idr.yield %n : i64
    }
    default(%d: i1) {
      idr.yield %n : i64
    }
    }
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
