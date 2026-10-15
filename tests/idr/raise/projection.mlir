// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@greet,not-called=@put,not-called=@done -o /dev/null
// NEEDS-ACCEPTANCE: that the projection and dispatch fold in the root once @greet is inlined.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// An IO action is a closure in a constructor (MkIO). When the result of a
// call is projected and applied at once, the projection and the dispatch
// the apply became meet, once the root inlines @greet, the constant action
// of one region and the constructor of the other, and both fold to a call
// of the closure's function, inlined in turn: nothing is called.
!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!IORes = !idr.data<"IORes", plain [@MkIORes(!Unit, !idr.world)]>
!IO = !idr.data<"IO", plain [@MkIO(!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)]>
idr.program @projection root(@Main.main) stage(higher) {
  idr.func @put(%n: i64, %w: !idr.world) -> !IORes attributes {total} {
    %w1 = idr.io.put_int signed %n, %w : i64
    %u = idr.con !Unit @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !Unit, %w1 : !idr.world)
    return %r : !IORes
  }
  idr.func @done(%w: !idr.world) -> !IORes attributes {total} {
    %u = idr.con !Unit @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !Unit, %w : !idr.world)
    return %r : !IORes
  }
  idr.func @greet(%n: i64) -> !IO attributes {total} {
    %done = idr.constant #idr.con<!IO, @MkIO, [#idr.closure<@done, []>]> : !IO
    %r = idr.match_lit %n : i64 -> (!IO) {
    case 0 {
      idr.yield %done : !IO
    }
    default {
      %k = idr.closure @put(%n) : (i64) -> !idr.fn<(!idr.world) -> (!IORes)>
      %k_lin = idr.lin.enter %k : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
      %io = idr.con !IO @MkIO(%k_lin : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
      idr.yield %io : !IO
    }
    }
    return %r : !IO
  }
  idr.func @Main.main(%w: !idr.world) -> !IORes {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %a = idr.call @greet(%n) : (i64) -> !IO
    %f = idr.field %a : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %r = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r : !IORes
  }
}
