// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@g:arg0:[@add],calls=@g:@add' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=labels=@g:arg0:[@add],calls=@g:@add' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@g:arg0:[]' -o /dev/null
// BEFORE-DAG: expected labels: @g {{.*}}
// BEFORE-DAG: expected calls: @g {{.*}}@add
// STDIN:
// The solve follows every edge the ops declare, whether or not the path
// runs: here the one call of @g is in the region a match on a constant
// never takes, and the closure it passes still reaches @g's parameter.
// So @g's parameter holds @add and its apply calls it; which regions run
// is the optimizer's to find afterwards, as a case of a known literal.
// The program means after the pass what it meant before it, on every input
// (the differential); no property here held before the pass, and each list
// of labels with one changed fails after it, so each sum is exactly its
// labels.
idr.program @"untaken-region" root(@Prog.main) stage(higher) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @g(%f: !idr.fn<(i64) -> (i64)>) -> i64 {
    %one = arith.constant 1 : i64
    %r = idr.apply %f(%one) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %k = arith.constant 2 : i64
    %c = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %zero = arith.constant 0 : i64
    %r = idr.match_lit %zero : i64 -> (i64) {
    case 0 {
      idr.yield %zero : i64
    }
    default(%d: i64) {
      %v = idr.call @g(%c) : (!idr.fn<(i64) -> (i64)>) -> i64
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
}
