// RUN: sed 's/Prog[.]count/idris_rt_live_cells/g' %s > %t.defines.mlir
// RUN: %status 3 idris-mlir -c %t.defines.mlir -o %t.defines.o 2> %t.defines.err
// RUN: grep -q 'unsupported (program):.* idris_rt_live_cells[ ,]' %t.defines.err
// RUN: test ! -e %t.defines.o
// RUN: sed 's/Prog[.]count/write/g' %s > %t.refers.mlir
// RUN: %status 3 idris-mlir -c %t.refers.mlir -o %t.refers.o 2> %t.refers.err
// RUN: grep -q 'unsupported (program):.* write[ ,]' %t.refers.err
// RUN: test ! -e %t.refers.o
// RUN: sed 's/Prog[.]count/idris_rt_cell/g' %s > %t.cell.mlir
// RUN: %status 3 idris-mlir -c %t.cell.mlir -o %t.cell.o 2> %t.cell.err
// RUN: grep -q 'unsupported (program):.* idris_rt_cell[ ,]' %t.cell.err
// RUN: test ! -e %t.cell.o
// RUN: sed 's/Prog[.]count/read/g' %s > %t.read.mlir
// RUN: %status 3 idris-mlir -c %t.read.mlir -o %t.read.o 2> %t.read.err
// RUN: grep -q 'unsupported (program):.* read[ ,]' %t.read.err
// RUN: test ! -e %t.read.o
// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 7 %t
// A program defines no symbol the runtime defines or refers to: the
// runtime's own references to it would bind to the program's definition
// wherever the runtime's code is linked in. idris-mlir refuses such a module
// before linking, naming the symbol, whether the runtime defines it (one of
// its functions: idris_rt_live_cells, idris_rt_cell) or only calls it (the C
// library's write and read); under a name of its own the same program
// compiles and runs.
idr.program @"runtime-names" root(@Prog.main) stage(higher) types #idr.types<> {
  idr.func @Prog.count(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    default(%d0: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = idr.call @Prog.count(%m) : (i64) -> i64
      %s = arith.addi %t, %one : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 7 : i64
    %r = idr.call @Prog.count(%c) : (i64) -> i64
    return %r : i64
  }
}
