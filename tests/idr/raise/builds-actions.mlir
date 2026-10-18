// NEEDS-ACCEPTANCE: that the call of @actions carries @actions's entry, none, once @actions is final (idr.call's effects, mlir-12), so it is raised across the output, with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument).
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@actions -o /dev/null
// A callee that only builds an IO action performs no IO when it runs: it
// makes constructors of @put's closure, which writes, and calls nothing
// that writes, so its effects summary is none. @actions builds
// `put x *> ...` for each element of a list, as for_ does over a list
// known only at runtime; it loops, so it is never inlined, and its call is
// raised across the output between it and the dispatch that runs its
// action: the raised call takes the world that output leaves, and the
// original is no longer called.
!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!IORes = !idr.data<"IORes", plain [@MkIORes(!Unit, !idr.world)]>
!IO = !idr.data<"IO", plain [@MkIO(!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)]>
!L = !idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"builds-actions" root(@Main.main) stage(higher) {
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
  // Runs %a, then %b.
  idr.func @then(%a: !idr.fn<(!idr.world) -> (!IORes)>, %b: !IO, %w: !idr.world) -> !IORes attributes {total} {
    %r = idr.apply %a(%w) : !idr.fn<(!idr.world) -> (!IORes)>
    %w1 = idr.field %r : !IORes @MkIORes[1] -> !idr.world
    %f = idr.field %b : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %s = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
    return %s : !IORes
  }
  idr.func @actions(%xs: !idr.box<!L>) -> !IO attributes {total} {
    %io = idr.match %xs : !idr.box<!L> -> (!IO) {
    case @Nil() {
      %k = idr.closure @done() : () -> !idr.fn<(!idr.world) -> (!IORes)>
      %k_lin = idr.lin.enter %k : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
      %a = idr.con !IO @MkIO(%k_lin : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
      idr.yield %a : !IO
    }
    case @Cons(%h: i64, %t: !idr.box<!L>) {
      %rest = idr.call @actions(%t) : (!idr.box<!L>) -> !IO
      %p = idr.closure @put(%h) : (i64) -> !idr.fn<(!idr.world) -> (!IORes)>
      %k = idr.closure @then(%p, %rest) : (!idr.fn<(!idr.world) -> (!IORes)>, !IO) -> !idr.fn<(!idr.world) -> (!IORes)>
      %k_lin = idr.lin.enter %k : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
      %a = idr.con !IO @MkIO(%k_lin : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
      idr.yield %a : !IO
    }
    }
    return %io : !IO
  }
  // A list known only at runtime: a loop, which nothing inlines.
  idr.func @read(%n: i64) -> !idr.box<!L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!L>) {
    case 0 {
      %nil = idr.con !idr.box<!L> @Nil()
      idr.yield %nil : !idr.box<!L>
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %t = idr.call @read(%m) : (i64) -> !idr.box<!L>
      %xs = idr.con !idr.box<!L> @Cons(%n : i64, %t : !idr.box<!L>)
      idr.yield %xs : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @Main.main(%w: !idr.world) -> !IORes {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %xs = idr.call @read(%n) : (i64) -> !idr.box<!L>
    %a = idr.call @actions(%xs) : (!idr.box<!L>) -> !IO
    %w2 = idr.io.put_int signed %n, %w1 : i64
    %w3 = idr.io.put_int signed %n, %w2 : i64
    %f = idr.field %a : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %s = idr.apply %f(%w3) : !idr.fn<(!idr.world) -> (!IORes)>
    return %s : !IORes
  }
}
