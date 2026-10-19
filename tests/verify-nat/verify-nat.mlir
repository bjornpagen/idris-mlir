// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A natural is never negative, and the type is what proves it: no op makes
// a !idr.nat that could be negative, and a constant cannot be one.

idr.program @nat root(@root) stage(first) {
  idr.func @negative_constant() -> !idr.nat {
    // expected-error @+1 {{cannot hold}}
    %n = idr.constant !idr.nat #idr.big<-1>
    return %n : !idr.nat
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// The difference of two naturals may be negative: it is Integer's.
idr.program @nat root(@root) stage(first) {
  idr.func @difference(%a: !idr.nat) -> !idr.nat {
    // expected-error @+1 {{must be}}
    %d = "idr.big.sub"(%a, %a) : (!idr.nat, !idr.nat) -> !idr.nat
    return %d : !idr.nat
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @nat root(@root) stage(first) {
  idr.func @mixed(%a: !idr.nat, %b: !idr.big) -> !idr.nat {
    // expected-error @+1 {{all of {lhs, rhs} have same type}}
    %s = "idr.big.add"(%a, %b) : (!idr.nat, !idr.big) -> !idr.nat
    return %s : !idr.nat
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// Only a natural that is not zero has a predecessor that is natural.
idr.program @nat root(@root) stage(first) {
  idr.func @integer_predecessor(%a: !idr.big) -> !idr.big {
    // expected-error @+1 {{operand #0 must be}}
    %p = "idr.big.pred"(%a) : (!idr.big) -> !idr.big
    return %p : !idr.big
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// An Integer becomes a natural only through idr.nat.from_big, which clamps.
idr.program @nat root(@root) stage(first) {
  idr.func @unclamped(%a: !idr.big) -> !idr.nat {
    // expected-error @+1 {{must be a natural at any grade}}
    %n = "idr.nat.to_big"(%a) : (!idr.big) -> !idr.nat
    return %n : !idr.nat
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// An integer becomes a natural only read as unsigned, which it then is:
// only idr.big.from_uint makes one.
idr.program @nat root(@root) stage(first) {
  idr.func @signed_word(%x: i64) -> !idr.nat {
    // expected-error @+1 {{but got '!idr.nat'}}
    %n = idr.big.from_sint %x : i64 : !idr.nat
    return %n : !idr.nat
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @nat root(@root) stage(first) {
  idr.func @negative_key(%n: !idr.nat) -> i64 {
    // expected-error @+1 {{that is not a literal of '!idr.nat'}}
    %r = idr.match_lit %n : !idr.nat -> (i64) {
    case #idr.big<-1> {
      %a = arith.constant 1 : i64
      idr.yield %a : i64
    }
    default(%d: !idr.nat) {
      %b = arith.constant 0 : i64
      idr.yield %b : i64
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
