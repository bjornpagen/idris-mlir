// RUN: idris-mlir-opt %s | FileCheck %s
// RUN: idris-mlir-opt %s --mlir-use-nameloc-as-prefix | FileCheck %s --check-prefix=NAMED
// The printer names a value for what it is: the world `w`, a string `s`,
// an Integer or a natural `n`, a closure `f`, a suspension `lazy`, a token
// `tok`, a graded value as its carrier; a constant by its kind or its
// constructor, a constructor by its name, a closure `clo`, a suspension
// `thunk`, a forced value `forced`, an applied one `applied`,
// a call's result by its callee's short name before its instance's
// arguments, and a case's fields `f0`, `f1`, .... A value whose location
// names the Idris binder it came from takes that name when the printer is
// asked to. A repeated name is numbered apart, which no check reads.
// CHECK-LABEL: idr.func private @values(
// CHECK-SAME: %w: !idr.world, %s: !idr.lin<!idr.str>, %n: !idr.big, %[[N:n_[0-9]+]]: !idr.nat, %f: !idr.fn<(i64) -> i64>, %lazy: !idr.lazy<i64>, %tok: !idr.token, %[[X:[a-z0-9_]+]]: i64)
// CHECK: %str = constant "a" : !idr.str
// CHECK: %big = constant #idr.big<"5"> : !idr.big
// CHECK: %nat = constant #idr.big<"3"> : !idr.nat
// CHECK: %clo = constant #idr.closure<@inc, []> : !idr.fn<(i64) -> i64>
// CHECK: %thunk = constant #idr.closure<@later, []> : !idr.lazy<i64>
// CHECK: %nothing = constant #idr.con<@Nothing, []> : !Maybe_Nat
// CHECK: %just = con @Just(%[[N]])
// CHECK: %clo{{_[0-9]+}} = closure @inc()
// CHECK: %thunk{{_[0-9]+}} = delay %{{.*}} : i64 -> !idr.lazy<i64>
// CHECK: %thunk{{_[0-9]+}} = suspend @later()
// CHECK: %forced = force %lazy
// CHECK: %applied = apply %f(%[[X]])
// CHECK: %lin = idr.lin.enter %[[X]]
// CHECK: %show = call @"Prelude.Show.show[Prelude.Types.Nat]"(%[[N]])
// CHECK: %inc = call @inc(%[[X]])
// CHECK: match %{{.*}} : !Point -> (i64) {
// CHECK-NEXT: case @MkPoint(%f0: i64, %f1: i64) {
// NAMED-LABEL: idr.func private @values(
// NAMED-SAME: %count: i64)
// NAMED: %forced = force %lazy
// NAMED: %result = apply %f(%count)
// NAMED: match %{{.*}} : !Point -> (i64) {
// NAMED-NEXT: case @MkPoint(%px: i64, %py: i64) {

!Prelude.Types.Maybe_Prelude.Types.Nat_ = !idr.data<"Prelude.Types.Maybe[Prelude.Types.Nat]", plain [@Nothing(), @Just(!idr.nat)]>
!Main.Point = !idr.data<"Main.Point", plain [@MkPoint(i64, i64)]>
idr.func private @"Prelude.Show.show[Prelude.Types.Nat]"(%a0: !idr.nat) -> !idr.str {
  idr.crash "no body"
  ub.unreachable
}
idr.func private @inc(%x: i64) -> i64 {
  return %x : i64
}
idr.func private @later() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
idr.func private @values(%w: !idr.world, %s: !idr.lin<!idr.str>, %b: !idr.big, %n: !idr.nat,
                         %f: !idr.fn<(i64) -> (i64)>, %l: !idr.lazy<i64>, %t: !idr.token,
                         %x: i64 loc("count"))
    -> (!idr.world, i64, !idr.str) {
  %c0 = idr.constant "a" : !idr.str
  %c1 = idr.constant #idr.big<"5"> : !idr.big
  %c2 = idr.constant #idr.big<"3"> : !idr.nat
  %c3 = idr.constant #idr.closure<@inc, []> : !idr.fn<(i64) -> (i64)>
  %c4 = idr.constant #idr.closure<@later, []> : !idr.lazy<i64>
  %c5 = idr.constant #idr.con<@Nothing, []>
      : !Prelude.Types.Maybe_Prelude.Types.Nat_
  %v0 = idr.con @Just(%n)
      : (!idr.nat) -> !Prelude.Types.Maybe_Prelude.Types.Nat_
  %v1 = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
  %one = arith.constant 1 : i64
  %v3 = idr.delay %one : i64 -> !idr.lazy<i64>
  %v4 = idr.suspend @later() : () -> !idr.lazy<i64>
  %v5 = idr.force %l : !idr.lazy<i64> -> i64
  %v6 = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)> loc("result")
  %v7 = idr.lin.enter %x : !idr.lin<i64>
  %v8 = idr.call @"Prelude.Show.show[Prelude.Types.Nat]"(%n) : (!idr.nat) -> !idr.str
  %v9 = idr.call @inc(%x) : (i64) -> i64
  %p = idr.con @MkPoint(%x, %x) : (i64, i64) -> !Main.Point
  %r = idr.match %p : !Main.Point -> (i64) {
  case @MkPoint(%px: i64 loc("px"), %py: i64 loc("py")) {
    %sum = arith.addi %px, %py : i64
    idr.yield %sum : i64
  }
  }
  return %w, %r, %v8 : !idr.world, i64, !idr.str
}
