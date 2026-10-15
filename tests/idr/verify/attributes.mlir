// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// NEEDS-ACCEPTANCE: the texts of the unknown-attribute errors and of the stack rule are C02's and C14's; the data types are C01's syntax.
// The dialect declares no discardable attribute: every fact of an op is
// its own property, so no pass can drop one. MLIR asks the dialect about
// every name with its prefix, so an attribute with it is refused, not
// ignored, the old marks of a whole program and of a stack cell included;
// an attribute of no dialect is read by whoever wrote it, as idr-expect
// reads its marks.

idr.func private @f(%a: i64, %b: i64) -> i64 {
  // expected-error @+1 {{has an unknown idr attribute "idr.nonsense"}}
  %q = idr.div signed %a, %b {idr.nonsense} : i64
  return %q : i64
}

// -----

// What a function is made from is its location; nothing else says it.
module {
  // expected-error @+1 {{has an unknown idr attribute "idr.origin"}}
  idr.func private @f(%x: i64) -> i64 attributes {idr.origin = "f"} {
    return %x : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// The root is the one public function; no mark turns the module's rules on.
// expected-error @+1 {{has an unknown idr attribute "idr.program"}}
module attributes {idr.program} {
}

// -----

// A stack cell is the con's own property, never an attribute beside it.
!L = !idr.data<"L", plain [@Nil()]>
idr.func private @f() -> i64 {
  // expected-error @+1 {{has an unknown idr attribute "idr.stack"}}
  %l = idr.con @Nil() {idr.stack} : () -> !idr.box<!L>
  %z = arith.constant 0 : i64
  return %z : i64
}

// -----

!T = !idr.data<"T", plain [@A(i64)]>
idr.func private @f(%x: i64) -> !T {
  // expected-error @+1 {{expects stack only on an idr.con of a box}}
  %t = idr.con @A(%x) stack : (i64) -> !T
  return %t : !T
}

// -----

// What the verifier accepts: the facts as the function's own, the stack
// property of a box's con, the marks idr-expect reads, and attributes of
// no dialect.
!L = !idr.data<"L", plain [@Nil()]>
module {
  idr.func private @f(%x: i64 {sample.x}) -> i64
      attributes {total, effects = #idr.effects<none>, junk} {
    %d = idr.div signed %x, %x {expect.facts = "delay"} : i64
    return %d : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    %l = idr.con @Nil() stack : () -> !idr.box<!L>
    %r = idr.call @f(%c) {expect.facts = "delay"} : (i64) -> i64
    return %r : i64
  }
}
