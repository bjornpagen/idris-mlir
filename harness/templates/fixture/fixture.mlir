// RUN: idris-mlir-opt %s --idr-expect=holds=folded=@f -o /dev/null
// What the test checks, in a sentence, stated as properties idr-expect
// checks of the module as written, rather than as the ops that happen to
// show them; no pass is run, so none is named. A module is one
// idr.program, which names its root, of type () -> i64, and its stage
// (higher before the closures become sums, first after it, then graded,
// owned and lowered). A data type is the family it is, written where it
// occurs: !idr.data<#Family[indices]>.
idr.program @fixture root(@f) stage(first) {
  idr.func @f() -> i64 {
    %four = arith.constant 4 : i64
    idr.return %four : i64
  }
}
