// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s --check-prefix=BEFORE
// RUN: idris-mlir-opt %s --remove-dead-values | FileCheck %s --check-prefix=AFTER
// An op declares which operands it takes the references of, and upstream's
// passes see that as an effect once idr-rc has graded the operand owned: a
// Free of the reference it held. Before idr-rc a constructor of plain
// fields takes nothing over and only computes, so an unused one goes. One
// of an owned field holds that reference until the drop that gives it
// back, and remove-dead-values keeps both: the function's verifier, which
// counts the references of a function holding an owned value, checks the
// module after the pass.
// BEFORE-LABEL: idr.func private @plain(
// BEFORE-NOT: {{(idr\.| )con }}
// BEFORE: return
// AFTER-LABEL: idr.func private @owned(
// AFTER: %[[P:.*]] = con @P::@P(%{{.*}}) : (!idr.own<!idr.str>) -> !idr.own<!P>
// AFTER: drop %[[P]] : !idr.own<!P>
// AFTER: return
module {
  idr.data @P {
    idr.ctor @P (!idr.str)
  }
  idr.func private @plain(%s: !idr.str) -> i64 {
    %p = idr.con @P::@P(%s) : (!idr.str) -> !idr.data<@P>
    %z = arith.constant 0 : i64
    return %z : i64
  }
  idr.func private @owned(%s: !idr.own<!idr.str>) -> i64 {
    %p = idr.con @P::@P(%s) : (!idr.own<!idr.str>) -> !idr.own<!idr.data<@P>>
    idr.drop %p : !idr.own<!idr.data<@P>>
    %z = arith.constant 0 : i64
    return %z : i64
  }
  idr.func @main(%s: !idr.str, %t: !idr.own<!idr.str>) -> (i64, i64) {
    %a = idr.call @plain(%s) : (!idr.str) -> i64
    %b = idr.call @owned(%t) : (!idr.own<!idr.str>) -> i64
    return %a, %b : i64, i64
  }
}
