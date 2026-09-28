// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// rule: IDR-FN-1, IDR-FACT-1, CORE-INV-3

// expected-error @+1 {{argument 0 has quantity "w" and type '!idr.erased'; quantity "0" is exactly for !idr.erased}}
func.func private @f(%e: !idr.erased {idr.quantity = "w"}) {
  return
}

// -----

// expected-error @+1 {{argument 1 has quantity "0" and type 'i64'; quantity "0" is exactly for !idr.erased}}
func.func private @f(%e: !idr.erased {idr.quantity = "0"}, %x: i64 {idr.quantity = "0"}) {
  return
}

// -----

// expected-error @+1 {{expects idr.quantity = "0", "1" or "w" on argument 0}}
func.func private @f(%x: i64 {idr.quantity = "2"}) {
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

// expected-error @+1 {{expects idr.effect = "pure" or "effectful" on a function}}
func.func private @f() attributes {idr.effect = "io"} {
  return
}

// -----

// expected-error @+1 {{expects idr.may_crash as a unit attribute of a function}}
func.func private @f() attributes {idr.may_crash = "yes"} {
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
func.func private @f(%e: !idr.erased {idr.quantity = "0"}, %x: i64 {idr.quantity = "1"},
                     %y: i64 {idr.quantity = "w"})
    attributes {idr.total, idr.effect = "pure", idr.may_crash, no_inline} {
  return
}
