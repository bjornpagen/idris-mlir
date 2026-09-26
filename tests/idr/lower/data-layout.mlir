// RUN: idris-mlir-opt %s --idr-check-input --idr-entry --idr-lower | FileCheck %s
// rule: LOW-DATA-1, LOW-DATA-2, LOW-DATA-3, LOW-ERASE-1, LOW-SWITCH-1, LOW-UP-1
// S has three constructors, so an i8 tag; B's i32 and C's flattened P
// (i64, i8) get separate slots; the erased field has none.
// CHECK-NOT: idr.
// CHECK-LABEL: func.func private @f(
// CHECK-SAME: %[[TAG:.*]]: i8, %[[B0:.*]]: i32, %[[P0:.*]]: i64, %[[P1:.*]]: i8) -> i64
// CHECK: arith.index_castui %[[TAG]] : i8 to index
// CHECK: scf.index_switch
// CHECK: arith.extsi %[[B0]]
// CHECK: scf.yield %[[P0]] : i64
// CHECK-LABEL: func.func private @Prog.main()
// CHECK-DAG: %[[FIVE:.*]] = arith.constant 5 : i32
// CHECK-DAG: %[[ONE:.*]] = arith.constant 1 : i8
// CHECK-DAG: %[[U1:.*]] = ub.poison : i64
// CHECK-DAG: %[[U2:.*]] = ub.poison : i8
// CHECK: call @f(%[[ONE]], %[[FIVE]], %[[U1]], %[[U2]])
// CHECK-LABEL: func.func @main() -> i32
// CHECK: call @Prog.main()
// CHECK: arith.trunci
module attributes {idr.version = 0 : i64, idr.entry = @Prog.main, idr.entry_kind = "int"} {
  idr.data @P attributes {idr.name = "P"} {
    idr.ctor @MkP tag 0 fields [i64, i8] quantities ["w", "w"] {idr.name = "MkP"}
  }
  idr.data @S attributes {idr.name = "S"} {
    idr.ctor @A tag 0 fields [] quantities [] {idr.name = "A"}
    idr.ctor @B tag 1 fields [i32, !idr.erased] quantities ["w", "0"] {idr.name = "B"}
    idr.ctor @C tag 2 fields [!idr.data<@P>] quantities ["1"] {idr.name = "C"}
  }
  func.func private @f(%s: !idr.data<@S> {idr.quantity = "w"}) -> i64 attributes {idr.name = "f"} {
    %t = idr.tag %s : !idr.data<@S>
    %r = scf.index_switch %t -> i64
    case 1 {
      %x = idr.field %s[@B, 0] : !idr.data<@S> -> i32
      %y = arith.extsi %x : i32 to i64
      scf.yield %y : i64
    }
    case 2 {
      %p = idr.field %s[@C, 0] : !idr.data<@S> -> !idr.data<@P>
      %z = idr.field %p[@MkP, 0] : !idr.data<@P> -> i64
      scf.yield %z : i64
    }
    default {
      %c = arith.constant 0 : i64
      scf.yield %c : i64
    }
    return %r : i64
  }
  func.func private @Prog.main() -> i64 attributes {idr.name = "main"} {
    %a = arith.constant 5 : i32
    %e = idr.erased : !idr.erased
    %s = idr.con @S::@B(%a, %e) : (i32, !idr.erased) -> !idr.data<@S>
    %r = func.call @f(%s) : (!idr.data<@S>) -> i64
    return %r : i64
  }
}
