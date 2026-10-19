// RUN: idris-mlir-opt %s --idr-defunctionalize --canonicalize --idr-expect=holds=builds=@wrap -o /dev/null
// A constructor, a closure or a suspension of constants folds to a
// constant, but poison is no constant a value can hold: one with a poison
// field stays an op. Here the apply's result is poison, since no label
// reaches it, and the constructor of it is still built.
!Box = !idr.data<"Box", plain [@MkBox(i64)]>
idr.program @"poison-fields" root(@Prog.main) stage(higher) {
  idr.func @wrap(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> !idr.box<!Box> {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %b = idr.con !idr.box<!Box> @MkBox(%y : i64)
    return %b : !idr.box<!Box>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
