// RUN: idris-mlir %s -o %t
// RUN: test -s %t.objects/*.o
// RUN: %status 42 %t
// Without -c, idris-mlir links what it compiled, from a module as from
// Idris source, with the pinned clang and the runtime, into the executable
// -o names; its objects stay beside it, in the directory named from it.
idr.program @link root(@Prog.main) stage(higher) types #idr.types<> {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
