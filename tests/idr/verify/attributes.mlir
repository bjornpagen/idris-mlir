// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// NEEDS-ACCEPTANCE: the texts of the unknown-attribute errors and of the stack rule, and the data types' syntax.
// The dialect declares no discardable attribute: every fact of an op is
// its own property, so no pass can drop one. MLIR asks the dialect about
// every name with its prefix, so an attribute with it is refused, not
// ignored, the old marks of a whole program and of a stack cell included;
// an attribute of no dialect is read by whoever wrote it, as idr-expect
// reads its marks.

idr.program @attributes root(@root) stage(first) {
  idr.func @f(%a: i64, %b: i64) -> i64 {
    // expected-error @+1 {{has an unknown idr attribute "idr.nonsense"}}
    %q = idr.div signed %a, %b {idr.nonsense} : i64
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

// A stack cell is the con's own property, never an attribute beside it.
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

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @attributes root(@root) stage(first) {
  idr.func @f(%x: i64) -> !T {
    // expected-error @+1 {{expects stack only on an idr.con of a box}}
    %t = idr.con !T @A(%x : i64) stack
    return %t : !T
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// What the verifier accepts: the facts as the function's own, the stack
// property of a box's con, the marks idr-expect reads, and attributes of
// no dialect.
!L = !idr.data<"L", plain [@Nil()]>
idr.program @attributes root(@main) stage(first) {
  idr.func @f(%x: i64 {sample.x}) -> i64
      attributes {total, effects = #idr.effects<none>, junk} {
    %d = idr.div signed %x, %x {expect.facts = "delay"} : i64
    return %d : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    %l = idr.con !idr.box<!L> @Nil() stack
    %r = idr.call @f(%c) {expect.facts = "delay"} : (i64) -> i64
    return %r : i64
  }
}
