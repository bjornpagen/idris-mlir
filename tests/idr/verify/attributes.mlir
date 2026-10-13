// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The dialect's discardable attributes are two marks: idr.program on the
// module of a whole program and idr.stack on an idr.con of a box whose
// cell never leaves its frame. MLIR asks the dialect about every name with
// its prefix, so any other is refused, not ignored; an attribute of no
// dialect is read by whoever wrote it, as idr-expect reads its marks.

idr.func private @f(%a: i64, %b: i64) -> i64 {
  // expected-error @+1 {{has an unknown idr attribute "idr.nonsense"}}
  %q = idr.div signed %a, %b {idr.nonsense} : i64
  return %q : i64
}

// -----

// A clone's key says what it was copied from; nothing else does.
module attributes {idr.program} {
  // expected-error @+1 {{has an unknown idr attribute "idr.origin"}}
  idr.func private @f.spec1(%x: i64) -> i64 attributes {idr.origin = "f"} {
    return %x : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// expected-error @+1 {{expects idr.program as a unit attribute of the module}}
idr.func private @f() attributes {idr.program} {
  return
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
idr.func private @f(%x: i64) -> !idr.data<@T> {
  // expected-error @+1 {{expects idr.stack as a unit attribute of an idr.con of a box}}
  %t = idr.con @T::@A(%x) {idr.stack} : (i64) -> !idr.data<@T>
  return %t : !idr.data<@T>
}

// -----

idr.data @L box {
  idr.ctor @Nil ()
}
idr.func private @f() -> i64 {
  // expected-error @+1 {{expects idr.stack as a unit attribute of an idr.con of a box}}
  %l = idr.con @L::@Nil() {idr.stack = 1 : i64} : () -> !idr.box<@L>
  %z = arith.constant 0 : i64
  return %z : i64
}

// -----

// What the verifier accepts: the facts as the function's own, the marks
// idr-expect reads, and attributes of no dialect.
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @Nil ()
  }
  idr.func private @f(%x: i64 {sample.x}) -> i64
      attributes {total, effects = #idr.effects<none>, junk,
                  clone = #idr.clone<@f, #idr.key_apply<"g", 1>>} {
    %d = idr.div signed %x, %x {expect.facts = "delay"} : i64
    return %d : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    %l = idr.con @L::@Nil() {idr.stack} : () -> !idr.box<@L>
    %r = idr.call @f(%c) {expect.facts = "delay"} : (i64) -> i64
    return %r : i64
  }
}
