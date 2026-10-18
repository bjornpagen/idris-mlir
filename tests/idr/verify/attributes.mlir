// NEEDS-ACCEPTANCE: the texts of the unknown-attribute errors and of the refusals rule, and that the frontend's refusals verify on the top-level module alone; the stack property and the expect.facts marks are gone (S3, mlir-23).
// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// No fact of an op is a discardable attribute: every one is the op's own
// property or a type, so no pass can drop one. MLIR asks the dialect about
// every name with its prefix, so an attribute with it is refused, not
// ignored, the old marks of a whole program and of a stack cell included;
// an attribute of no dialect is no business of ours. The one name the
// dialect declares is the frontend's report to the driver, idr.refusals,
// which no pass reads.

idr.program @attributes root(@root) stage(first) {
  idr.func @f(%a: i64, %b: i64) -> i64 {
    // expected-error @+1 {{has an unknown idr attribute "idr.nonsense"}}
    %q = idr.divs %a, %b {idr.nonsense} : i64
    return %q : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// What a function is made from is its location; nothing else says it.
idr.program @attributes root(@main) stage(first) {
  // expected-error @+1 {{has an unknown idr attribute "idr.origin"}}
  idr.func @f(%x: i64) -> i64 attributes {idr.origin = "f"} {
    return %x : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// A program is an op, idr.program, which names its root; no mark on a
// module turns a program's rules on.
// expected-error @+1 {{has an unknown idr attribute "idr.program"}}
module attributes {idr.program} {
}

// -----

// A cell of the frame is an op of its own, idr.cell.stack, never an
// attribute beside a con.
!L = !idr.data<"L", plain [@Nil()]>
idr.program @attributes root(@f) stage(first) {
  idr.func @f() -> i64 {
    // expected-error @+1 {{has an unknown idr attribute "idr.stack"}}
    %l = idr.con !idr.box<!L> @Nil() {idr.stack}
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// What the verifier accepts: the facts as the function's own, and
// attributes of no dialect.
idr.program @attributes root(@main) stage(first) {
  idr.func effects<none> @f(%x: i64 {sample.x}) -> i64
      attributes {total, junk} {
    %d = idr.divs %x, %x : i64
    return %d : i64
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
// expected-error @+1 {{has "idr.refusals", which is an array of #idr.refusal on the top-level module alone}}
module attributes {idr.refusals = ["cycle"]} {
}

// -----

module {
  // expected-error @+1 {{has "idr.refusals", which is an array of #idr.refusal on the top-level module alone}}
  module attributes {idr.refusals = []} {
  }
}
