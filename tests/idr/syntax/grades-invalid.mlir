// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A grade written out is checked as any other: the verifier's canonical
// forms, and the parser's spellings of a quantity.

// expected-error @+1 {{expects a grade other than (many, plain), which is the plain type}}
func.func private @plain(!idr.q<many, plain, i64>)

// -----

// expected-error @+1 {{expects the world at (one, plain)}}
func.func private @world(!idr.q<many, own, !idr.world_carrier>)

// -----

// expected-error @+1 {{expects a grade of a plain type, got one of}}
func.func private @graded(!idr.q<one, own, !idr.lin<i64>>)

// -----

// expected-error @+1 {{expects nothing owned at quantity zero}}
func.func private @erased(!idr.q<zero, own, none>)

// -----

// expected-error @+2 {{expected ::idr::Quantity to be one of: zero, one, many}}
// expected-error @+1 {{parameter 'quantity' which is to be a `::idr::Quantity`}}
func.func private @two(!idr.q<two, plain, i64>)
