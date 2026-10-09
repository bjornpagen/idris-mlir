// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s --check-prefix=BEFORE
// RUN: idris-mlir-opt %s --remove-dead-values | FileCheck %s --check-prefix=AFTER
// An op declares which operands it takes the references of, and upstream's
// passes see that as an effect once idr-rc has graded the operand owned: a
// Free of the reference it held. Before idr-rc a constructor of plain
// fields takes nothing over and only computes, so an unused one goes. One
// of an owned field holds that reference, so remove-dead-values keeps it
// even unused, as it keeps a drop, rather than lose the reference with it.
// (Neither function is a program's, so no verifier asks where the
// reference goes next.)
// BEFORE-LABEL: func.func private @plain(
// BEFORE-NOT: idr.con
// BEFORE: return
// AFTER-LABEL: func.func private @owned(
// AFTER: idr.con @P::@P(%{{.*}}) : (!idr.own<!idr.str>) -> !idr.own<!idr.data<@P>>
// AFTER: return
module {
  idr.data @P {
    idr.ctor @P (!idr.str)
  }
  func.func private @plain(%s: !idr.str) -> i64 {
    %p = idr.con @P::@P(%s) : (!idr.str) -> !idr.data<@P>
    %z = arith.constant 0 : i64
    return %z : i64
  }
  func.func private @owned(%s: !idr.own<!idr.str>) -> i64 {
    %p = idr.con @P::@P(%s) : (!idr.own<!idr.str>) -> !idr.own<!idr.data<@P>>
    %z = arith.constant 0 : i64
    return %z : i64
  }
  func.func @main(%s: !idr.str, %t: !idr.own<!idr.str>) -> (i64, i64) {
    %a = func.call @plain(%s) : (!idr.str) -> i64
    %b = func.call @owned(%t) : (!idr.own<!idr.str>) -> i64
    return %a, %b : i64, i64
  }
}
