// RUN: idris-mlir-opt %s --pass-pipeline="builtin.module(idr-round-facts, idr.func(idr-redirect))" > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --pass-pipeline="builtin.module(idr-round-facts, idr.func(idr-redirect))" > %t2.mlir
// RUN: diff %t.mlir %t2.mlir
// The redirect half of specialization, function by function: a call whose
// key the module's clones already hold calls that clone, and makes none.
// @apply is on no cycle, so it specializes on the closure it is given; the
// clone for a closure of @add over a runtime value is here. Both calls that
// pass such a closure call it with the closure's capture, whatever its
// value, and the closures they built go. The first call's effects hold the
// clone's, so it keeps them; the second carries none, and takes none. A
// closure of @sub has no clone, and its call waits for idr-specialize. A
// second run changes nothing.
// CHECK-LABEL: idr.func private @use(
// CHECK-SAME: %[[N:[a-z0-9_]+]]: i64, %[[M:[a-z0-9_]+]]: i64, %[[X:[a-z0-9_]+]]: i64)
// CHECK-NOT: closure @add
// CHECK: %[[H:.*]] = {{(idr\.)?}}closure @sub(%[[N]])
// CHECK-NEXT: call @[[SPEC:[^ (]+]](%[[N]], %[[X]]) effects = <none> : (i64, i64) -> i64
// CHECK-NEXT: call @[[SPEC]](%[[M]], %[[X]]) : (i64, i64) -> i64
// CHECK-NEXT: call @apply(%[[H]], %[[X]]) : (!idr.fn<(i64) -> i64>, i64) -> i64
// CHECK-NOT: closure @add
// CHECK: return
module attributes {idr.program} {
  idr.func private @add(%a: i64, %x: i64) -> i64 attributes {effects = #idr.effects<none>, total} {
    %y = arith.addi %a, %x : i64
    idr.return %y : i64
  }
  idr.func private @sub(%a: i64, %x: i64) -> i64 attributes {effects = #idr.effects<none>, total} {
    %y = arith.subi %a, %x : i64
    idr.return %y : i64
  }
  idr.func private @apply(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {effects = #idr.effects<none>, total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    idr.return %y : i64
  }
  idr.func private @apply.spec1(%a: i64, %x: i64) -> i64 attributes {clone = #idr.clone<@apply.spec1, #idr.spec_key<"apply", [#idr.key_closure<"add", [#idr.key_hole<0>]>, #idr.key_hole<1>]>>, effects = #idr.effects<none>, total} {
    %y = idr.call @add(%a, %x) effects = <none> : (i64, i64) -> i64
    idr.return %y : i64
  }
  idr.func private @use(%n: i64, %m: i64, %x: i64) -> (i64, i64, i64) attributes {effects = #idr.effects<none>, total} {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @add(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
    %h = idr.closure @sub(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r1 = idr.call @apply(%f, %x) effects = <none> : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %r2 = idr.call @apply(%g, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %r3 = idr.call @apply(%h, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    idr.return %r1, %r2, %r3 : i64, i64, i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %r:3 = idr.call @use(%x, %x, %x) : (i64, i64, i64) -> (i64, i64, i64)
    %w2 = idr.io.put_int signed %r#0, %w1 : i64
    %w3 = idr.io.put_int signed %r#1, %w2 : i64
    %w4 = idr.io.put_int signed %r#2, %w3 : i64
    idr.return %w4 : !idr.world
  }
}
