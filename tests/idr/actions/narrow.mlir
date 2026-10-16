// NEEDS-ACCEPTANCE: that skipping every idr-narrow-version, idr-narrow-joint, idr-narrow-word, idr-narrow-fold and idr-narrow-erase action leaves the module as idr-narrow received it, and that idr-narrow changes it otherwise.
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-rc,idr.func(idr-tail-loops)))' -o %t.in.mlir
// RUN: idris-mlir-opt %t.in.mlir -o %t.none.mlir
// RUN: idris-mlir-opt %t.in.mlir --pass-pipeline='builtin.module(idr.program(idr-narrow))' --mlir-disable-threading -mlir-debug-counter=idr-narrow-version-count=0,idr-narrow-joint-count=0,idr-narrow-word-count=0,idr-narrow-fold-count=0,idr-narrow-erase-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %t.in.mlir --pass-pipeline='builtin.module(idr.program(idr-narrow))' -o %t.done.mlir
// RUN: not diff %t.none.mlir %t.done.mlir
idr.program @descending root(@root) stage(first) {
  idr.func @parity(%n: !idr.nat, %odd: i1) -> i1 attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (i1) {
    case #idr.big<0> {
      idr.yield %odd : i1
    }
    default {
      %k = idr.big.pred %n
      %true = arith.constant true
      %flip = arith.xori %odd, %true : i1
      %s = idr.call @parity(%k, %flip) : (!idr.nat, i1) -> i1
      idr.yield %s : i1
    }
    }
    return %r : i1
  }
  idr.func @count(%n: !idr.nat, %acc: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %acc : !idr.nat
    }
    default {
      %k = idr.big.pred %n
      %two = idr.constant #idr.big<2> : !idr.nat
      %more = idr.big.add %acc, %two : !idr.nat
      %s = idr.call @count(%k, %more) : (!idr.nat, !idr.nat) -> !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }
  idr.func @Main.main(%n: !idr.nat) -> (i1, !idr.nat) {
    %false = arith.constant false
    %p = idr.call @parity(%n, %false) : (!idr.nat, i1) -> i1
    %zero = idr.constant #idr.big<0> : !idr.nat
    %c = idr.call @count(%n, %zero) : (!idr.nat, !idr.nat) -> !idr.nat
    return %p, %c : i1, !idr.nat
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
