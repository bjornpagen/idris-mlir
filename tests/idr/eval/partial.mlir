// RUN: idris-mlir-opt %s --mlir-disable-threading --idr-eval --remarks-filter=idr-eval 2> %t.remarks > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=REMARK < %t.remarks
// A closed call of pure code Idris does not prove terminating is evaluated
// as one of total code is, but metered. @down ends for its argument, so its
// call is a constant. The others never end: @spin loops by tail recursion,
// @deep recurses, @grow allocates as it recurses, @loop goes round a loop
// that idr-tail-loops would have made, and @applyTo, total itself, applies
// a closure of @spin. Each spends its budget and stays, to run at runtime,
// with a Missed remark; the calls after it in the round still run.
// CHECK-LABEL: func.func @Prog.main()
// CHECK-DAG: %[[D:.*]] = arith.constant 42 : i64
// CHECK-DAG: %[[S:.*]] = call @spin(%{{.*}}) : (i64) -> i64
// CHECK-DAG: %[[E:.*]] = call @deep(%{{.*}}) : (i64) -> i64
// CHECK-DAG: %[[G:.*]] = call @grow(%{{.*}}) : (i64) -> !idr.box<@List>
// CHECK-DAG: %[[L:.*]] = call @loop(%{{.*}}) : (i64) -> i64
// CHECK-DAG: %[[A:.*]] = call @applyTo(%{{.*}}) : (!idr.fn<(i64) -> (i64)>) -> i64
// CHECK: return %[[D]], %[[S]], %[[E]], %[[G]], %[[L]], %[[A]]
// REMARK-DAG: remark: [Passed] Evaluated {{.*}}Function=down
// REMARK-DAG: remark: [Missed] Unfinished {{.*}}Function=spin{{.*}}budget
// REMARK-DAG: remark: [Missed] Unfinished {{.*}}Function=deep
// REMARK-DAG: remark: [Missed] Unfinished {{.*}}Function=grow
// REMARK-DAG: remark: [Missed] Unfinished {{.*}}Function=loop
// REMARK-DAG: remark: [Missed] Unfinished {{.*}}Function=applyTo
module {
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  func.func private @down(%n: i64) -> i64 attributes {idr.effects = #idr.effects<none>} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %v = arith.constant 42 : i64
      idr.yield %v : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %d = func.call @down(%m) : (i64) -> i64
      idr.yield %d : i64
    }
    }
    return %r : i64
  }
  func.func private @spin(%x: i64) -> i64 attributes {idr.effects = #idr.effects<none>} {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    %r = func.call @spin(%y) : (i64) -> i64
    return %r : i64
  }
  func.func private @deep(%x: i64) -> i64 attributes {idr.effects = #idr.effects<none>} {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    %r = func.call @deep(%y) : (i64) -> i64
    %s = arith.muli %r, %x : i64
    return %s : i64
  }
  func.func private @grow(%x: i64) -> !idr.box<@List> attributes {idr.effects = #idr.effects<none>} {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    %rest = func.call @grow(%y) : (i64) -> !idr.box<@List>
    %c = idr.con @List::@Cons(%x, %rest) : (i64, !idr.box<@List>) -> !idr.box<@List>
    return %c : !idr.box<@List>
  }
  func.func private @loop(%x: i64) -> i64 attributes {idr.effects = #idr.effects<none>} {
    %r = scf.while (%i = %x) : (i64) -> i64 {
      idr.may_loop
      %go = arith.constant true
      scf.condition(%go) %i : i64
    } do {
    ^bb0(%j: i64):
      %one = arith.constant 1 : i64
      %k = arith.addi %j, %one : i64
      scf.yield %k : i64
    }
    return %r : i64
  }
  func.func private @applyTo(%f: !idr.fn<(i64) -> (i64)>) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %one = arith.constant 1 : i64
    %r = idr.apply %f(%one) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @Prog.main() -> (i64, i64, i64, !idr.box<@List>, i64, i64) {
    %thousand = arith.constant 1000 : i64
    %zero = arith.constant 0 : i64
    %s = func.call @spin(%zero) : (i64) -> i64
    %e = func.call @deep(%zero) : (i64) -> i64
    %g = func.call @grow(%zero) : (i64) -> !idr.box<@List>
    %l = func.call @loop(%zero) : (i64) -> i64
    %p = idr.constant #idr.closure<@spin, []> : !idr.fn<(i64) -> (i64)>
    %a = func.call @applyTo(%p) : (!idr.fn<(i64) -> (i64)>) -> i64
    %d = func.call @down(%thousand) : (i64) -> i64
    return %d, %s, %e, %g, %l, %a : i64, i64, i64, !idr.box<@List>, i64, i64
  }
}
