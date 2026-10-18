// NEEDS-ACCEPTANCE: that each region's dispatch meets the constructors @greet builds once it is inlined, as the inner pipeline folds them, with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument, ir-ods-8's type-first constant).
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@greet,not-called=@put,not-called=@done -o /dev/null
// The result of a call used in each region of a match, applied there
// through the field of MkIO. @greet is small and final when the root is
// cleaned, so the root inlines it; each region's dispatch then meets the
// constructor of the action @greet built (case of case brings it in) and
// folds to a direct call of @put or @done, inlined in turn, after the
// output the other region does. Nothing is called.
!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!IORes = !idr.data<"IORes", plain [@MkIORes(!Unit, !idr.world)]>
!IO = !idr.data<"IO", plain [@MkIO(!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)]>
idr.program @branches root(@Main.main) stage(higher) {
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
    %done = idr.constant !IO #idr.con<!IO, @MkIO, [#idr.closure<@done, []>]>
    %r = idr.match_lit %n : i64 -> (!IO) {
    case 0 {
      idr.yield %done : !IO
    }
    default(%d: i64) {
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
    %r = idr.match_lit %n : i64 -> (!IORes) {
    case 0 {
      %f = idr.field %a : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
      %s = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
      idr.yield %s : !IORes
    }
    default(%d: i64) {
      %w2 = idr.io.put_int signed %n, %w1 : i64
      %f = idr.field %a : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
      %s = idr.apply %f(%w2) : !idr.fn<(!idr.world) -> (!IORes)>
      idr.yield %s : !IORes
    }
    }
    return %r : !IORes
  }
}
