// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A natural is never negative, and the type is what proves it: no op makes
// a !idr.nat that could be negative, and a constant cannot be one.

func.func @negative_constant() -> !idr.nat {
  // expected-error @+1 {{cannot hold}}
  %n = idr.constant #idr.big<"-1"> : !idr.nat
  return %n : !idr.nat
}

// -----

// The difference of two naturals may be negative: it is Integer's.
func.func @difference(%a: !idr.nat) -> !idr.nat {
  // expected-error @+1 {{must be}}
  %d = idr.big.sub %a, %a : !idr.nat
  return %d : !idr.nat
}

// -----

func.func @mixed(%a: !idr.nat, %b: !idr.big) -> !idr.nat {
  // expected-error @+1 {{all of {lhs, rhs, result} have same type}}
  %s = "idr.big.add"(%a, %b) : (!idr.nat, !idr.big) -> !idr.nat
  return %s : !idr.nat
}

// -----

// Only a natural that is not zero has a predecessor that is natural.
func.func @integer_predecessor(%a: !idr.big) -> !idr.big {
  // expected-error @+1 {{must be a natural number}}
  %p = "idr.big.pred"(%a) : (!idr.big) -> !idr.big
  return %p : !idr.big
}

// -----

// An Integer becomes a natural only through idr.nat.from_big, which clamps.
func.func @unclamped(%a: !idr.big) -> !idr.nat {
  // expected-error @+1 {{must be a natural number}}
  %n = "idr.nat.to_big"(%a) : (!idr.big) -> !idr.nat
  return %n : !idr.nat
}

// -----

func.func @negative_key(%n: !idr.nat) -> i64 {
  // expected-error @+1 {{that is not a literal of '!idr.nat'}}
  %r = idr.match_lit %n : !idr.nat -> (i64) {
  case #idr.big<"-1"> {
    %a = arith.constant 1 : i64
    idr.yield %a : i64
  }
  default {
    %b = arith.constant 0 : i64
    idr.yield %b : i64
  }
  }
  return %r : i64
}
