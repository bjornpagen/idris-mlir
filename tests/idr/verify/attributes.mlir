// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// Every attribute is read by someone. An inherent one is its op's; a
// discardable one names the dialect that verifies it, or is one of the few
// our own tools read. MLIR asks a dialect only about the names with its
// prefix, so the idr ops and the functions of a program reject any other.

idr.data @T {
  // expected-error @+1 {{has the attribute "quantities", which no dialect defines}}
  idr.ctor @A (i64) {quantities = ["w"]}
}

// -----

func.func private @f(%a: i64, %b: i64) -> i64 {
  // expected-error @+1 {{has the attribute "anything", which no dialect defines}}
  %q = idr.div signed %a, %b {anything = "goes"} : i64
  return %q : i64
}

// -----

func.func private @f(%a: i64, %b: i64) -> i64 {
  // expected-error @+1 {{has an unknown idr attribute "idr.nonsense"}}
  %q = idr.div signed %a, %b {idr.nonsense} : i64
  return %q : i64
}

// -----

// A clone's key says what it was copied from; nothing else does.
module attributes {idr.program} {
  // expected-error @+1 {{has an unknown idr attribute "idr.origin"}}
  func.func private @f$spec$1(%x: i64) -> i64 attributes {idr.origin = "f"} {
    return %x : i64
  }
  func.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

module attributes {idr.program} {
  // expected-error @+1 {{has the attribute "junk", which no dialect defines}}
  func.func @main() -> i64 attributes {junk} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

module attributes {idr.program} {
  // expected-error @+1 {{has the attribute "junk" on argument 0, which no dialect defines}}
  func.func private @f(%x: i64 {junk}) -> i64 {
    return %x : i64
  }
  func.func @main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

module attributes {idr.program} {
  func.func @main() -> i64 {
    // expected-error @+1 {{has the attribute "junk", which no dialect defines}}
    %c = arith.constant {junk} 0 : i64
    return %c : i64
  }
}

// -----

// What the verifier accepts: the dialect's own attributes where they
// belong, another dialect's, and the marks idr-expect reads.
module attributes {idr.program} {
  func.func private @f(%x: i64 {idr.hole = 0 : i64}) -> i64
      attributes {idr.total, idr.effects = #idr.effects<none>,
                  idr.clone = #idr.clone<@f, #idr.key_apply<"g", 1>>} {
    %d = idr.div signed %x, %x {expect.facts = "delay"} : i64
    return %d : i64
  }
  func.func @main() -> i64 attributes {llvm.emit_c_interface} {
    %c = arith.constant 0 : i64
    %r = func.call @f(%c) {expect.facts = "delay"} : (i64) -> i64
    return %r : i64
  }
}
