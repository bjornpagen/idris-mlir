// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A grade written out is checked as any other: the verifier's canonical
// forms, and the parser's spellings of a quantity.

// expected-error @+1 {{expects a grade other than (many, plain), which is the plain type}}
idr.func private @plain(!idr.q<many, plain, i64>)

// -----

// expected-error @+1 {{expects the world at (one, plain)}}
idr.func private @world(!idr.q<many, own, !idr.world_carrier>)

// -----

// expected-error @+1 {{expects a grade of a plain type, got one of}}
idr.func private @graded(!idr.q<one, own, !idr.lin<i64>>)

// -----

// A value of quantity zero has no runtime representation, so no grade holds
// one: a grade is of a runtime type.
// expected-error @+1 {{expects a grade of a runtime type, got 'none'}}
idr.func private @none(!idr.q<one, plain, none>)

// -----

// expected-error @+2 {{expected ::idr::Quantity to be one of: one, many}}
// expected-error @+1 {{parameter 'quantity' which is to be a `::idr::Quantity`}}
idr.func private @two(!idr.q<two, plain, i64>)
