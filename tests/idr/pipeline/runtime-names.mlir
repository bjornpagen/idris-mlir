// RUN: sed 's/Prog[.]count/idris_rt_live_cells/g' %s > %t.defines.mlir
// RUN: %status 1 idris-mlir -c %t.defines.mlir -o %t.defines.o --no-eval 2> %t.defines.err
// RUN: grep -q 'the program defines idris_rt_live_cells, which the runtime defines too' %t.defines.err
// RUN: test ! -e %t.defines.o
// RUN: sed 's/Prog[.]count/write/g' %s > %t.refers.mlir
// RUN: %status 1 idris-mlir -c %t.refers.mlir -o %t.refers.o --no-eval 2> %t.refers.err
// RUN: grep -q 'the program defines write, which the runtime refers to too' %t.refers.err
// RUN: test ! -e %t.refers.o
// RUN: idris-mlir -c %s -o %t.o --no-eval
// RUN: %cc %t.o -o %t
// RUN: %status 7 %t
// A program defines no symbol the runtime defines or refers to: the
// runtime's own references to it would bind to the program's definition
// wherever the runtime's code is linked in. idris-mlir refuses such a
// module before linking, naming the symbol, whether the runtime defines it
// (one of its functions) or only calls it (the C library's write); under a
// name of its own the same program compiles and runs.
module attributes {idr.program} {
  func.func private @Prog.count(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = func.call @Prog.count(%m) : (i64) -> i64
      %s = arith.addi %t, %one : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %c = arith.constant 7 : i64
    %r = func.call @Prog.count(%c) : (i64) -> i64
    return %r : i64
  }
}
