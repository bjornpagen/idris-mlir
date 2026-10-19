// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 1 %t > %t.out 2> %t.err
// RUN: FileCheck %s --check-prefix=ERR < %t.err
// A crash names the place in the source its location holds, wherever in
// the location it is: here a call site's caller, its callee unknown.
// ERR: idris-mlir: unhandled input for Main.pick at Main.idr:9:3
idr.program @"crash-callsite" root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    idr.crash "unhandled input for Main.pick" loc(callsite(unknown at "Main.idr":9:3))
    ub.unreachable
  }
}
