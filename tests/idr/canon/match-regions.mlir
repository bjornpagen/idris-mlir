// NEEDS-ACCEPTANCE: a match's default region is first and binds the scrutinee (S2): two defaults ("expected '}'"), a default without its argument ("expected '('"), a default that binds another type ("expects a default region that takes the scrutinee back at its type") and `cases` in the attribute dictionary ("inherent attribute 'cases' cannot be parsed from attr-dict") are refused; an exhaustive idr.match, whose default is empty, merges its two equal cases into a default that binds the scrutinee, and its field read moves into its regions (case-of-case), under upstream's canonicalize with region simplification disabled.
// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// RUN: awk '/^\/\/ -----/ { n++; next } n == 4' %s > %t.exhaustive.mlir
// RUN: idris-mlir-opt %t.exhaustive.mlir --canonicalize=region-simplify=disabled \
// RUN: --idr-expect=holds=regions-distinct=@exhaustive,matches=@exhaustive,builds-nothing=@exhaustive,\
// RUN: reads-fields=@exhaustive -o /dev/null
// RUN: idris-mlir-opt %t.exhaustive.mlir '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// A match's regions are the default's, then one per case. A default that
// runs binds the scrutinee back at its type, and is written once, after
// the cases; its cases are the ones its syntax spells, never an attribute.

idr.program @"match-regions" root(@root) stage(first) {
  idr.func @f(%v: i64) {
    idr.match_lit %v : i64 -> () {
    case 0 {
      idr.yield
    }
    default(%d: i64) {
      idr.yield
    }
    // expected-error @+1 {{expected '}'}}
    default(%e: i64) {
      idr.yield
    }
    }
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64), @B()]>
idr.program @"match-regions" root(@root) stage(first) {
  idr.func @f(%v: !T) {
    idr.match %v : !T -> () {
    case @A(%x: i64) {
      idr.yield
    }
    // expected-error @+1 {{expected '('}}
    default {
      idr.yield
    }
    }
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64), @B()]>
idr.program @"match-regions" root(@root) stage(first) {
  idr.func @f(%v: !T) {
    // expected-error @+1 {{expects a default region that takes the scrutinee back at its type}}
    idr.match %v : !T -> () {
    case @A(%x: i64) {
      idr.yield
    }
    default(%d: i64) {
      idr.yield
    }
    }
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T", plain [@A(i64), @B()]>
idr.program @"match-regions" root(@root) stage(first) {
  idr.func @f(%v: !T) {
    // expected-error @+1 {{inherent attribute 'cases' cannot be parsed from attr-dict}}
    idr.match %v : !T -> () attributes {cases = array<i32: 1>} {
    case @A(%x: i64) {
      idr.yield
    }
    }
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// An exhaustive match has an empty default. Its two equal cases become a
// default that binds the scrutinee back, and the field read of its result
// moves into its regions, where it meets the constructor it reads: what is
// left is one match of a case and a default, which reads a field of %p,
// and nothing is built.
!C = !idr.data<"C", plain [@R(), @G(i64), @B()]>
!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.program @"match-regions" root(@root) stage(first) {
  idr.func @exhaustive(%c: !C, %p: !P) -> i64 {
    %q = idr.match %c : !C -> (!P) {
    case @R() {
      idr.yield %p : !P
    }
    case @G(%f: i64) {
      %one = arith.constant 1 : i64
      %made = idr.con !P @MkP(%f : i64, %one : i64)
      idr.yield %made : !P
    }
    case @B() {
      idr.yield %p : !P
    }
    }
    %first = idr.field %q : !P @MkP[0] -> i64
    return %first : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
