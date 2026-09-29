// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

// A parameter's quantity is its type.
// expected-error @+1 {{has an unknown idr argument attribute "idr.quantity"}}
func.func private @f(%x: i64 {idr.quantity = "1"}) {
  return
}

// -----

// expected-error @+1 {{has an unknown idr argument attribute "idr.linear"}}
func.func private @f(%x: i64 {idr.linear}) {
  return
}

// -----

// expected-error @+1 {{expects idr.total as a unit attribute of a function}}
func.func private @f() attributes {idr.total = 1 : i64} {
  return
}

// -----

// expected-error @+1 {{expects idr.effects = #idr.effects<...> on a function}}
func.func private @f() attributes {idr.effects = "io"} {
  return
}

// -----

// expected-error @+1 {{expects idr.library as a unit attribute of a function}}
func.func private @f() attributes {idr.library = "yes"} {
  return
}

// -----

func.func private @f() {
  // expected-error @+1 {{has an unknown idr attribute "idr.entry"}}
  %c = arith.constant {idr.entry} 0 : i64
  return
}

// -----

// The facts a function may carry.
func.func private @f(%e: !idr.erased, %x: i64,
                     %y: i64)
    attributes {idr.total, idr.library, idr.effects = #idr.effects<io, crash>, no_inline} {
  return
}
