// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@greet,not-called=@put -o /dev/null
// NEEDS-ACCEPTANCE: that the linear enter and use of the action fold away, as the canonicalizer folds a use of an enter.
// An IO action is linear: the result of @greet enters a linear position
// and is used at once before its field is applied. The pair only moves
// the action in and out, and folds away, so once the root inlines @greet
// the dispatch meets the constructor @greet built and calls @put
// directly, which it inlines: nothing is called.
!IORes = !idr.data<"IORes", plain [@MkIORes(i64, !idr.world)]>
!IO = !idr.data<"IO", plain [@MkIO(!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)]>
module {
  idr.func private @put(%n: i64, %w: !idr.world) -> !IORes attributes {total} {
    %w1 = idr.io.put_int signed %n, %w : i64
    %r = idr.con @MkIORes(%n, %w1) : (i64, !idr.world) -> !IORes
    return %r : !IORes
  }
  idr.func private @greet(%n: i64) -> !IO attributes {total} {
    %k = idr.closure @put(%n) : (i64) -> !idr.fn<(!idr.world) -> (!IORes)>
    %k_lin = idr.lin.enter %k : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con @MkIO(%k_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>) -> !IO
    return %io : !IO
  }
  idr.func @Main.main(%w: !idr.world) -> !IORes {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %io = idr.call @greet(%n) : (i64) -> !IO
    %in = idr.lin.enter %io : !idr.lin<!IO>
    %out = idr.lin.use %in : !idr.lin<!IO>
    %f = idr.field %out[@MkIO, 0] : !IO -> !idr.fn<(!idr.world) -> (!IORes)>
    %r = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r : !IORes
  }
}
