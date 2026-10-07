// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The verifier errors that the custom syntax cannot produce, in the generic
// form.

idr.data @T {
  idr.ctor @A ()
}
func.func @f(%v: !idr.data<@T>) {
  // expected-error @+1 {{expects one region per case and at most one default}}
  "idr.match"(%v) <{cases = [@A]}> ({
    "idr.yield"() : () -> ()
  }, {
    "idr.yield"() : () -> ()
  }, {
    "idr.yield"() : () -> ()
  }) : (!idr.data<@T>) -> ()
  return
}

// -----

idr.data @T {
  idr.ctor @A ()
}
func.func @f(%v: !idr.data<@T>) {
  // expected-error @+1 {{expects constructor names as cases, got 0 : i64}}
  "idr.match"(%v) <{cases = [0]}> ({
    "idr.yield"() : () -> ()
  }) : (!idr.data<@T>) -> ()
  return
}

// -----

idr.data @T {
  idr.ctor @A ()
}
func.func @f(%v: !idr.data<@T>) {
  // expected-error @+1 {{expects a default region without arguments}}
  "idr.match"(%v) <{cases = [@A]}> ({
    "idr.yield"() : () -> ()
  }, {
  ^bb0(%x: i64):
    "idr.yield"() : () -> ()
  }) : (!idr.data<@T>) -> ()
  return
}

// -----

func.func @f(%v: i64) {
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

func.func @f(%v: i64) {
  // expected-error @+1 {{has a key 0 : i32 that is not a literal of 'i64'}}
  "idr.match_lit"(%v) <{cases = [0 : i32]}> ({
    "idr.yield"() : () -> ()
  }, {
    "idr.yield"() : () -> ()
  }) : (i64) -> ()
  return
}

// -----

func.func @f(%v: i64) {
  // expected-error @+1 {{expects a non-empty block}}
  "idr.match_lit"(%v) <{cases = [0]}> ({
  ^bb0:
  }, {
    "idr.yield"() : () -> ()
  }) : (i64) -> ()
  return
}

// -----

func.func @f() {
  // expected-error @+1 {{has a constant of an undeclared type '!idr.data<@Nowhere>'}}
  %c = idr.constant #idr.con<@Nowhere::@A, []> : !idr.data<@Nowhere>
  return
}

// -----

func.func @f() {
  // expected-error @+1 {{expects a constructor reference @T::@C, got @T}}
  %c = idr.constant #idr.con<@T, []> : !idr.data<@T>
  return
}

// -----

// Stored values are untyped: the type is the op's.
func.func @f() {
  // expected-error @+1 {{cannot hold #idr.big<"1"> : !idr.big as '!idr.big'}}
  %c = "idr.constant"() <{value = #idr.big<"1"> : !idr.big}> : () -> !idr.big
  return
}
