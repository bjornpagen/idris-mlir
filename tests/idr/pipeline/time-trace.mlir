// RUN: idris-mlir-opt %s --idr-simplify --time-trace=%t.json > %t-traced.mlir
// RUN: idris-mlir-opt %s --idr-simplify > %t-plain.mlir
// RUN: diff %t-traced.mlir %t-plain.mlir
// RUN: FileCheck %s --check-prefix=TRACE < %t.json
// A time trace (--time-trace) records every pass and every analysis the
// simplify loop runs, with what each ran on, and the end of each round;
// writing one changes no byte of the module (the diff above).
// TRACE: "traceEvents"
// TRACE-DAG: "name":"Total IdrSimplify"
// TRACE-DAG: "name":"Total CanonicalizerPass"
// TRACE-DAG: "name":"Total idr::Effects"
// TRACE-DAG: "detail":"idr.func @Main.main"
// TRACE-DAG: "name":"round"
module attributes {idr.program} {
  idr.func private @count(%acc: !idr.big, %n: i64) -> !idr.big attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.big) {
    case 0 {
      idr.yield %acc : !idr.big
    }
    default {
      %one = idr.constant #idr.big<"1"> : !idr.big
      %c1 = arith.constant 1 : i64
      %a = idr.big.add %acc, %one
      %m = arith.subi %n, %c1 : i64
      %x = idr.call @count(%a, %m) : (!idr.big, i64) -> !idr.big
      idr.yield %x : !idr.big
    }
    }
    return %r : !idr.big
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %zero = idr.constant #idr.big<"0"> : !idr.big
    %r = idr.call @count(%zero, %n) : (!idr.big, i64) -> !idr.big
    %t = idr.big.show %r
    %w2 = idr.io.put_str %t, %w1
    return %w2 : !idr.world
  }
}
