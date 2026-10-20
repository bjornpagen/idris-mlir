// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A natural is never negative, and the type is what proves it: no op makes
// a !idr.nat that could be negative, and a constant cannot be one.

idr.program @nat root(@root) stage(first) types #idr.types<> {
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
idr.program @nat root(@root) stage(first) types #idr.types<> {
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

idr.program @nat root(@root) stage(first) types #idr.types<> {
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
idr.program @nat root(@root) stage(first) types #idr.types<> {
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
idr.program @nat root(@root) stage(first) types #idr.types<> {
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
idr.program @nat root(@root) stage(first) types #idr.types<> {
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

idr.program @nat root(@root) stage(first) types #idr.types<> {
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

// -----

// The nearest each refusal above has that verifies: the least natural, 0;
// the difference as an Integer, of the naturals made Integers; the sum of
// two naturals; the predecessor of a natural; the clamping conversion; the
// word read as unsigned; and a key that is a natural.
idr.program @nat root(@root) stage(first) types #idr.types<> {
  idr.func @zero_constant() -> !idr.nat {
    %n = idr.constant !idr.nat #idr.big<0>
    return %n : !idr.nat
  }
  idr.func @difference(%a: !idr.nat) -> !idr.big {
    %b = "idr.nat.to_big"(%a) : (!idr.nat) -> !idr.big
    %d = "idr.big.sub"(%b, %b) : (!idr.big, !idr.big) -> !idr.big
    return %d : !idr.big
  }
  idr.func @same(%a: !idr.nat, %b: !idr.nat) -> !idr.nat {
    %s = "idr.big.add"(%a, %b) : (!idr.nat, !idr.nat) -> !idr.nat
    return %s : !idr.nat
  }
  idr.func @natural_predecessor(%a: !idr.nat) -> !idr.nat {
    %p = "idr.big.pred"(%a) : (!idr.nat) -> !idr.nat
    return %p : !idr.nat
  }
  idr.func @clamped(%a: !idr.big) -> !idr.nat {
    %n = "idr.nat.from_big"(%a) : (!idr.big) -> !idr.nat
    return %n : !idr.nat
  }
  idr.func @unsigned_word(%x: i64) -> !idr.nat {
    %n = idr.big.from_uint %x : i64 : !idr.nat
    return %n : !idr.nat
  }
  idr.func @zero_key(%n: !idr.nat) -> i64 {
    %r = idr.match_lit %n : !idr.nat -> (i64) {
    case #idr.big<0> {
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
