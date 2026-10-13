// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: sed '/^\/\/ -----/,$d' %s > %t.facts.mlir
// RUN: idris-mlir-opt %t.facts.mlir -o %t.once.mlir
// RUN: idris-mlir-opt %t.once.mlir -o %t.twice.mlir
// RUN: cmp %t.once.mlir %t.twice.mlir
// RUN: FileCheck %s --implicit-check-not=idr.call --implicit-check-not=idr.return < %t.once.mlir
// What is known of a function is idr.func's own: Idris's proof (total),
// what the passes find (effects, no_inline, break_last) and what it is an
// instance or a clone of, each an inherent attribute, so no pass drops one
// without changing the op. They print after `attributes`, by name, and read
// back as themselves; the ops of the body print without the dialect's
// prefix. A fact of the wrong kind is refused when the op is read.
// CHECK-LABEL: idr.func private @f(
// CHECK-SAME: attributes {clone = #idr.clone<@f, #idr.spec_key<"Prelude.f", [#idr.key_hole<0>]>>, effects = #idr.effects<io, crash>, instance = #idr.instance<"Prelude.f", ["Prelude.Types.Nat"]>, no_inline, total} {
// CHECK-NEXT: {{^ *}}return %{{.*}} : i64
// CHECK-LABEL: idr.func private @g(
// CHECK-SAME: attributes {break_last} {
// CHECK-NEXT: {{^ *}}%[[R:.*]] = call @f(%{{.*}}) effects = <io, crash> : (i64) -> i64
// CHECK-NEXT: {{^ *}}return %[[R]] : i64

idr.func private @f(%x: i64) -> i64
    attributes {total, no_inline, effects = #idr.effects<io, crash>,
                instance = #idr.instance<"Prelude.f", ["Prelude.Types.Nat"]>,
                clone = #idr.clone<@f, #idr.spec_key<"Prelude.f", [#idr.key_hole<0>]>>} {
  return %x : i64
}
idr.func private @g(%x: i64) -> i64 attributes {break_last} {
  %r = call @f(%x) effects = <io, crash> : (i64) -> i64
  return %r : i64
}

// -----

// expected-error @+1 {{attribute 'total' failed to satisfy constraint: unit attribute}}
idr.func private @f() attributes {total = 1 : i64} {
  return
}
