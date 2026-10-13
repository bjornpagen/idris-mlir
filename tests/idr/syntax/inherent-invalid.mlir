// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A fact an op's syntax already spells (a match's cases, a constant's
// value) is inherent, set as a property by the custom parsers. Restated
// in the attr-dict it would become that property when the op is created,
// overriding the spelled one, or vanish if of the wrong kind; both are
// refused as the op is read, as the generated strict-properties parsers
// refuse them.

idr.data @T {
  idr.ctor @A (i64)
  idr.ctor @B ()
}
idr.func @f(%v: !idr.data<@T>) -> i64 {
  // expected-error @+1 {{attribute 'cases' failed to satisfy constraint: array attribute}}
  %r = idr.match %v : !idr.data<@T> -> (i64) attributes {cases = 1 : i64} {
  case @A(%x: i64) {
    idr.yield %x : i64
  }
  default {
    %z = arith.constant 0 : i64
    idr.yield %z : i64
  }
  }
  return %r : i64
}

// -----

idr.data @T {
  idr.ctor @A ()
  idr.ctor @B ()
}
idr.func @f(%v: !idr.data<@T>) -> i64 {
  // expected-error @+1 {{inherent attribute 'cases' cannot be parsed from attr-dict when strict properties in assembly format is enabled}}
  %r = idr.match %v : !idr.data<@T> -> (i64) attributes {cases = [@B]} {
  case @A() {
    %z = arith.constant 1 : i64
    idr.yield %z : i64
  }
  default {
    %z = arith.constant 0 : i64
    idr.yield %z : i64
  }
  }
  return %r : i64
}

// -----

idr.func @f(%n: i64) -> i64 {
  // expected-error @+1 {{attribute 'cases' failed to satisfy constraint: array attribute}}
  %r = idr.match_lit %n : i64 -> (i64) attributes {cases = "nope"} {
  case 0 {
    idr.yield %n : i64
  }
  default {
    idr.yield %n : i64
  }
  }
  return %r : i64
}

// -----

idr.func @f(%n: i64) -> i64 {
  // expected-error @+1 {{inherent attribute 'cases' cannot be parsed from attr-dict when strict properties in assembly format is enabled}}
  %r = idr.match_lit %n : i64 -> (i64) attributes {cases = [7 : i64]} {
  case 0 {
    idr.yield %n : i64
  }
  default {
    idr.yield %n : i64
  }
  }
  return %r : i64
}

// -----

idr.func @f() -> !idr.str {
  // expected-error @+1 {{inherent attribute 'value' cannot be parsed from attr-dict when strict properties in assembly format is enabled}}
  %s = idr.constant "hi" : !idr.str {value = 1 : i64}
  return %s : !idr.str
}
