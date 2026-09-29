// RUN: %status 1 bash -c 'ulimit -v 3000000; exec idris-mlir-opt %s --mlir-disable-threading --idr-eval' > %t.out 2> %t.err
// RUN: FileCheck %s < %t.err
// An evaluation that cannot finish is reported where the user's code is: a call inlined from a library
// carries its call-site chain, and the error is at the innermost frame that
// is not the library's, with its callers as notes.
// CHECK: Main.idr:5:7: error: unsupported (compile-time evaluation): the machine could not finish evaluating @range, which is total
// CHECK: Main.idr:9:3: note: called from here
module {
  idr.data @List box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.box<@List>) {quantities = ["w", "w"]}
  }
  func.func @Prog.main() -> !idr.box<@List> {
    %n = arith.constant 1000000000 : i64
    %l = func.call @range(%n) : (i64) -> !idr.box<@List> loc(callsite(fused<"library">["Prelude.idr":10:3] at callsite("Main.idr":5:7 at "Main.idr":9:3)))
    return %l : !idr.box<@List>
  }
  func.func private @range(%n: i64) -> !idr.box<@List> attributes {idr.total, idr.effect = "pure"} {
    %r = idr.match_lit %n : i64 -> (!idr.box<@List>) {
    case 0 {
      %nil = idr.con @List::@Nil() : () -> !idr.box<@List>
      idr.yield %nil : !idr.box<@List>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %rest = func.call @range(%m) : (i64) -> !idr.box<@List>
      %c = idr.con @List::@Cons(%n, %rest) : (i64, !idr.box<@List>) -> !idr.box<@List>
      idr.yield %c : !idr.box<@List>
    }
    }
    return %r : !idr.box<@List>
  }
}
