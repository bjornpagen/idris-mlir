// RUN: %status 2 idris-mlir -c %s -o %t.o -mlir-print-ir-module-scope -mlir-print-ir-after-all --report=%t.report 2> %t.err
// RUN: test ! -e %t.o
// RUN: test ! -e %t.report
// RUN: idris-mlir -c %s -o %t.o -mlir-print-ir-module-scope -mlir-print-ir-after-all --mlir-disable-threading 2> %t.printed
// RUN: test -s %t.o
// RUN: test -s %t.printed
// What MLIR's own options ask that the command line alone rules out is
// read with the command line, before anything runs: a usage error, which
// arms no output and writes no report. With threading off, the same
// options print the module after each pass.
idr.program @"print-ir-threads" root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
