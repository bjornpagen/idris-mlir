// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@f:4 -o /dev/null
// What the test checks, in a sentence, stated as properties idr-expect
// checks (idr/Transforms/Expect.h) rather than as the ops that happen to
// show them. A module is one idr.program, which names its root, of type
// () -> i64 or (!idr.world) -> (...), its stage (higher before
// idr-defunctionalize, first after it, owned after idr-rc) and its data
// types, each by its name with its body, in name order; a data type is
// its name wherever it occurs.
idr.program @fixture root(@f) stage(first) types #idr.types<> {
  idr.func @f() -> i64 {
    %two = arith.constant 2 : i64
    %four = arith.addi %two, %two : i64
    return %four : i64
  }
}
