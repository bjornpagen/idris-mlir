// RUN: idris-mlir %s -o %t
// RUN: test -s %t.o
// RUN: %status 42 %t
// Without -c, idris-mlir links what it compiled, from a module as from
// Idris source, with the pinned clang and the runtime, into the executable
// -o names; the object stays beside it, named from it.
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 42 : i64
    return %c : i64
  }
}
