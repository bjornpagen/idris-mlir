// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: sed '/^\/\/ -----/,$d' %s > %t.facts.mlir
// RUN: idris-mlir-opt %t.facts.mlir -o %t.once.mlir
// RUN: idris-mlir-opt %t.once.mlir -o %t.twice.mlir
// RUN: cmp %t.once.mlir %t.twice.mlir
// RUN: FileCheck %s --implicit-check-not=idr.call --implicit-check-not=idr.return < %t.once.mlir
// What is known of a function is idr.func's own: Idris's proof (total),
// what the frontend and the passes decide (no_inline, effects) and what it
// is an instance of, each inherent, so no pass drops one without changing
// the op. The effects, a property, print before the symbol; the others
// print after `attributes`, by name; each reads back as itself, and the ops
// of the body print without the dialect's prefix. A fact of the wrong kind
// is refused when the op is read, each of the three: the first split is
// the nearest each refusal has.
// CHECK-LABEL: idr.func effects<io, crash> @f(
// CHECK-SAME: attributes {instance = #idr.instance<"Prelude.f", ["Prelude.Types.Nat"]>, no_inline, total} {
// CHECK-NEXT: {{^ *}}return %{{.*}} : i64
// CHECK-LABEL: idr.func @g(
// CHECK-NEXT: {{^ *}}%[[R:.*]] = call @f(%{{.*}}) : (i64) -> i64
// CHECK-NEXT: {{^ *}}return %[[R]] : i64

idr.program @"facts-roundtrip" root(@root) stage(first) types #idr.types<> {
  idr.func effects<io, crash> @f(%x: i64) -> i64
      attributes {total, no_inline,
                  instance = #idr.instance<"Prelude.f", ["Prelude.Types.Nat"]>} {
    return %x : i64
  }
  idr.func @g(%x: i64) -> i64 {
    %r = call @f(%x) : (i64) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"facts-roundtrip" root(@root) stage(first) types #idr.types<> {
  // expected-error @+1 {{attribute 'total' failed to satisfy constraint: unit attribute}}
  idr.func @f() attributes {total = 1 : i64} {
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"facts-roundtrip" root(@root) stage(first) types #idr.types<> {
  // expected-error @+1 {{attribute 'no_inline' failed to satisfy constraint: unit attribute}}
  idr.func @f() attributes {no_inline = 1 : i64} {
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// An instance names the definition and its arguments; the name alone is
// of the wrong kind.
idr.program @"facts-roundtrip" root(@root) stage(first) types #idr.types<> {
  // expected-error @+1 {{attribute 'instance' failed to satisfy constraint}}
  idr.func @f() attributes {instance = "Prelude.f"} {
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
