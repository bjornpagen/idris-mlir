// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// NEEDS-ACCEPTANCE: the text of a constant naming no constructor of its type, as C02 writes it.
// The verifier errors that the custom syntax cannot produce, in the generic
// form.

!T = !idr.data<"T", plain [@A()]>
idr.func private @f(%v: !T) {
  // expected-error @+1 {{expects one region per case and at most one default}}
  "idr.match"(%v) <{cases = [@A]}> ({
    "idr.yield"() : () -> ()
  }, {
    "idr.yield"() : () -> ()
  }, {
    "idr.yield"() : () -> ()
  }) : (!T) -> ()
  return
}

// -----

!T = !idr.data<"T", plain [@A()]>
idr.func private @f(%v: !T) {
  // expected-error @+1 {{expects constructor names as cases, got 0 : i64}}
  "idr.match"(%v) <{cases = [0]}> ({
    "idr.yield"() : () -> ()
  }) : (!T) -> ()
  return
}

// -----

!T = !idr.data<"T", plain [@A()]>
idr.func private @f(%v: !T) {
  // expected-error @+1 {{expects a default region without arguments}}
  "idr.match"(%v) <{cases = [@A]}> ({
    "idr.yield"() : () -> ()
  }, {
  ^bb0(%x: i64):
    "idr.yield"() : () -> ()
  }) : (!T) -> ()
  return
}

// -----

idr.func private @f(%v: i64) {
  // expected-error @+1 {{expects regions without arguments}}
  "idr.match_lit"(%v) <{cases = [0]}> ({
  ^bb0(%x: i64):
    "idr.yield"() : () -> ()
  }, {
    "idr.yield"() : () -> ()
  }) : (i64) -> ()
  return
}

// -----

idr.func private @f(%v: i64) {
  // expected-error @+1 {{has a key 0 : i32 that is not a literal of 'i64'}}
  "idr.match_lit"(%v) <{cases = [0 : i32]}> ({
    "idr.yield"() : () -> ()
  }, {
    "idr.yield"() : () -> ()
  }) : (i64) -> ()
  return
}

// -----

idr.func private @f(%v: i64) {
  // expected-error @+1 {{expects a non-empty block}}
  "idr.match_lit"(%v) <{cases = [0]}> ({
  ^bb0:
  }, {
    "idr.yield"() : () -> ()
  }) : (i64) -> ()
  return
}

// -----

// A constant names a constructor of its own type's body.
!T = !idr.data<"T", plain [@C()]>
idr.func private @f() {
  // expected-error @+1 {{@D}}
  %c = idr.constant #idr.con<@D, []> : !T
  return
}

// -----

// Stored values are untyped: the type is the op's.
idr.func private @f() {
  // expected-error @+1 {{cannot hold #idr.big<"1"> : !idr.big as '!idr.big'}}
  %c = "idr.constant"() <{value = #idr.big<"1"> : !idr.big}> : () -> !idr.big
  return
}
