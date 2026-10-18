// NEEDS-ACCEPTANCE: the driver's diagnostic for an action log it cannot write, its one verdict exit 2.
// RUN: %status 2 idris-mlir -c %s -o %t.o --log-actions-to=%t.absent/actions.log 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: %status 1 test -e %t.o
// RUN: idris-mlir -c %s -o %t.o
// RUN: test -s %t.o
// An error fails the compilation wherever it is reported, also where what
// reports it goes on. MLIR's action logging reports a log file it cannot
// open as an error and runs without it: idris-mlir then stops with a
// usage error and writes no object. Without the error the module compiles.
// CHECK: idris-mlir: cannot write {{.*}}actions.log, which --log-actions-to names
idr.program @"reported-error-fails" root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
