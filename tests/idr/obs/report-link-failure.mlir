// NEEDS-ACCEPTANCE: a compilation whose --runtime names no file fails as the compiler's: exit 1, stderr idris-mlir: internal error: with the reason, a report of verdict internal with the error's diagnostic line, and no object.
// RUN: %status 1 idris-mlir -c %s -o %t.o --runtime=%t.absent/idris_rt.o --report=%t.report 2> %t.err
// RUN: FileCheck %s --check-prefix=ERR < %t.err
// RUN: FileCheck %s --check-prefix=REPORT < %t.report
// RUN: test ! -e %t.o
// Every failure of a step is a diagnostic of the compilation's: one that
// is the compiler's (a runtime that cannot be read) is printed in the
// driver's form with its class, folds the verdict and has its line in the
// report, as every diagnostic does.
// ERR: idris-mlir: internal error: cannot read runtime {{.*}}absent/idris_rt.o
// REPORT: verdict: internal
// REPORT-NEXT: diagnostic: error - -
// REPORT-NOT: diagnostic:
idr.program @"report-link-failure" root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
