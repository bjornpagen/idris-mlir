// NEEDS-ACCEPTANCE: a module with no idr.program holding a non-LLVM op is refused at that op, naming it, exit 1, verdict internal; a func.func module does not parse, exit 1, verdict internal.
// RUN: sed -n 's|^// HALFWAY: ||p' %s > %t.halfway.mlir
// RUN: %status 1 idris-mlir -c %t.halfway.mlir -o %t.halfway.o --report=%t.halfway.report 2> %t.halfway.err
// RUN: FileCheck %s --check-prefix=MIXERR < %t.halfway.err
// RUN: FileCheck %s --check-prefix=MIXED < %t.halfway.report
// RUN: sed -n 's|^// FUNCTIONS: ||p' %s > %t.functions.mlir
// RUN: %status 1 idris-mlir -c %t.functions.mlir -o %t.functions.o --report=%t.functions.report 2> %t.functions.err
// RUN: FileCheck %s --check-prefix=FUNCERR < %t.functions.err
// RUN: FileCheck %s --check-prefix=UNPARSED < %t.functions.report
// A module with no idr.program is the pipeline's output and holds only
// LLVM dialect ops. One lowered half way (an arith op left in an
// llvm.func) is no such module: idris-mlir says so at the op, as the
// compiler's error, before LLVM's translation meets it. A func.func, of a
// dialect neither the frontend nor the pipeline's output is written in,
// does not parse.
// MIXERR: error: 'arith.constant' op is no op of the LLVM dialect, in a module that holds no idr.program
// MIXED: verdict: internal
// MIXED-NEXT: diagnostic: error - {{.*}}.halfway.mlir:2{{$}}
// FUNCERR: error: {{.*}}'func.func'
// UNPARSED: verdict: internal
// UNPARSED-NEXT: diagnostic: error - {{.*}}.functions.mlir:1{{$}}
// HALFWAY: llvm.func @main() -> i64 {
// HALFWAY:   %c = arith.constant 42 : i64
// HALFWAY:   llvm.return %c : i64
// HALFWAY: }
// FUNCTIONS: func.func @main() -> i64 {
// FUNCTIONS:   %c = arith.constant 42 : i64
// FUNCTIONS:   return %c : i64
// FUNCTIONS: }
idr.program @"lowered-mixed" root(@Prog.main) stage(higher) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
