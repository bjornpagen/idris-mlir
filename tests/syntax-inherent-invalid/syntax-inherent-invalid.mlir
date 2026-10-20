// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A fact an op's syntax already spells (a match's cases, a constant's
// value) is inherent, set as a property by the custom parsers. Restated
// in the attr-dict, of the right kind or of another, it would override
// the spelled one or vanish, so it is refused as the op is read, as the
// generated strict-properties parsers refuse it. One split per op; the
// diagnostic is upstream's, so only the attribute it names is matched.
// The nearest each has that is read, the last split: the same ops with an
// attribute in the attr-dict that no op's syntax spells, of no dialect.

!T = !idr.data<"T">
#types = #idr.types<
  "T" = plain [@A(), @B()]
>
idr.program @"inherent-invalid" root(@root) stage(first) types #types {
  idr.func @f(%v: !T) -> i64 {
    // expected-error @+1 {{inherent attribute 'cases'}}
    %r = idr.match %v : !T -> (i64) attributes {cases = [@B]} {
    case @A() {
      %z = arith.constant 1 : i64
      idr.yield %z : i64
    }
    default(%d: !T) {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
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

idr.program @"inherent-invalid" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%n: i64) -> i64 {
    // expected-error @+1 {{inherent attribute 'cases'}}
    %r = idr.match_lit %n : i64 -> (i64) attributes {cases = [7 : i64]} {
    case 0 {
      idr.yield %n : i64
    }
    default(%d: i64) {
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

// -----

idr.program @"inherent-invalid" root(@root) stage(first) types #idr.types<> {
  idr.func @f() -> !idr.str {
    // expected-error @+1 {{inherent attribute 'value'}}
    %s = idr.constant !idr.str "hi" {value = 1 : i64}
    return %s : !idr.str
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T">
#types = #idr.types<
  "T" = plain [@A(), @B()]
>
idr.program @"inherent-invalid" root(@root) stage(first) types #types {
  idr.func @f(%v: !T, %n: i64) -> (i64, i64, !idr.str) {
    %r = idr.match %v : !T -> (i64) attributes {sample.cases = [@B]} {
    case @A() {
      %z = arith.constant 1 : i64
      idr.yield %z : i64
    }
    default(%d: !T) {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    %l = idr.match_lit %n : i64 -> (i64) attributes {sample.cases = [7 : i64]} {
    case 0 {
      idr.yield %n : i64
    }
    default(%d: i64) {
      idr.yield %n : i64
    }
    }
    %s = idr.constant !idr.str "hi" {sample.value = 1 : i64}
    return %r, %l, %s : i64, i64, !idr.str
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
