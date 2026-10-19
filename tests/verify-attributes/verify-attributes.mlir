// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// No fact of an op is a discardable attribute: every one is the op's own
// property or a type, so no pass can drop one. MLIR asks the dialect about
// every name with its prefix, so an attribute with it is refused, not
// ignored, on an op as on a function's argument; what is known of a
// parameter is its type. An attribute of no dialect is no business of
// ours. The one name the dialect declares is the frontend's report to the
// driver, idr.refusals, which no pass reads.

idr.program @attributes root(@root) stage(first) {
  idr.func @f(%a: i64, %b: i64) -> i64 {
    // expected-error @+1 {{has an unknown idr attribute "idr.nonsense"}}
    %q = idr.divs %a, %b {idr.nonsense} : i64
    return %q : i64
  }
  idr.func @root() -> i64 {
    %a = arith.constant 7 : i64
    %b = arith.constant 2 : i64
    %q = idr.call @f(%a, %b) : (i64, i64) -> i64
    return %q : i64
  }
}

// -----

idr.program @attributes root(@root) stage(first) {
  // expected-error @+1 {{has an unknown idr argument attribute "idr.nonsense"}}
  idr.func @f(%x: i64 {idr.nonsense = 0 : i64}) -> i64 {
    return %x : i64
  }
  idr.func @root() -> i64 {
    %z = arith.constant 0 : i64
    %r = idr.call @f(%z) : (i64) -> i64
    return %r : i64
  }
}

// -----

// What the verifier accepts, the nearest the two refusals above have: the
// facts as the function's own, and attributes, of an op, a function or an
// argument, of no dialect.
idr.program @attributes root(@main) stage(first) {
  idr.func effects<none> @f(%x: i64 {sample.x}) -> i64
      attributes {total, junk} {
    %d = idr.divs %x, %x {sample.y} : i64
    return %d : i64
  }
  idr.func effects<io, crash> @g(%x: !idr.lin<i64>, %y: i64)
      attributes {total, no_inline} {
    return
  }
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    %r = idr.call @f(%c) : (i64) -> i64
    return %r : i64
  }
}

// -----

// The frontend's refusals, which it writes into the module it hands the
// driver and the driver re-emits: the one idr attribute a module holds.
module attributes {idr.refusals = [#idr.refusal<cycle, loc("Main.idr":3:5), "an IORef of Node can hold a reference to itself">]} {
}

// -----

// Refusals are held by the module the frontend writes, as refusals.
// expected-error @+1 {{has "idr.refusals", which is a non-empty array of #idr.refusal on a module alone}}
module attributes {idr.refusals = ["cycle"]} {
}

// -----

// A refused module has a refusal.
// expected-error @+1 {{has "idr.refusals", which is a non-empty array of #idr.refusal on a module alone}}
module attributes {idr.refusals = []} {
}

// -----

// A module alone holds them, as the bytecode reader's own module holds the
// frontend's while it verifies it.
module {
  // expected-error @+1 {{has "idr.refusals", which is a non-empty array of #idr.refusal on a module alone}}
  idr.program @p root(@root) stage(higher) attributes {idr.refusals = [#idr.refusal<cycle, loc("Main.idr":3:5), "x">]} {
    idr.func @root() -> i64 {
      %z = arith.constant 0 : i64
      return %z : i64
    }
  }
}
