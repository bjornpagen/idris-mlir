// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-stack,idr-rc,idr.func(idr-tail-loops)))' | FileCheck %s
// NEEDS-ACCEPTANCE: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// Counting runs on functional code, and idr-tail-loops turns what it
// counted into loops, which keep the owned stage's rule (idris-mlir-opt
// verifies it after each pass). A consumer that only reads its list borrows
// it, and its loop carries the borrowed list with no count changed; a string
// built along the way is carried owned.
// CHECK-LABEL: idr.func @sumAcc(
// CHECK-SAME: %{{.*}}: i64, %{{.*}}: !idr.box<!L>)
// CHECK: scf.while
// CHECK-NOT: {{(idr\.| )dup }}
// CHECK-NOT: {{(idr\.| )drop }}
// CHECK-LABEL: idr.func @drain(
// CHECK-SAME: %{{.*}}: !idr.box<!L>, %{{.*}}: !idr.own<!idr.str>)
// CHECK: scf.while
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @loops root(@root) stage(first) {
  idr.func @sumAcc(%acc: i64, %l: !idr.box<!L>) -> i64 attributes {total} {
    %r = idr.match %l : !idr.box<!L> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %a = arith.addi %acc, %h : i64
      %s = idr.call @sumAcc(%a, %t) : (i64, !idr.box<!L>) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @drain(%l: !idr.box<!L>, %s: !idr.str) -> !idr.str attributes {total} {
    %r = idr.match %l : !idr.box<!L> -> (!idr.str) {
    case @N() {
      idr.yield %s : !idr.str
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %x = idr.str.show signed %h : i64
      %s2 = idr.str.append %s, %x
      %d = idr.call @drain(%t, %s2) : (!idr.box<!L>, !idr.str) -> !idr.str
      idr.yield %d : !idr.str
    }
    }
    return %r : !idr.str
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %l = idr.constant #idr.con<!L, @N, []> : !idr.box<!L>
    %z = arith.constant 0 : i64
    %n = idr.call @sumAcc(%z, %l) : (i64, !idr.box<!L>) -> i64
    %e = idr.constant "" : !idr.str
    %m = idr.constant #idr.con<!L, @C, [1, #idr.con<!L, @N, []>]> : !idr.box<!L>
    %s = idr.call @drain(%m, %e) : (!idr.box<!L>, !idr.str) -> !idr.str
    %w2 = idr.io.put_int signed %n, %w : i64
    %w3 = idr.io.put_str %s, %w2
    return %w3 : !idr.world
  }
}
