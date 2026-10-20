// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce))' -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@greet,not-called=@put,not-called=@done,not-called=@mk,not-called=@curry,not-called=@add -o /dev/null
// Once a callee is inlined, a dispatch on its result meets the constructor
// the inlined body built and folds to a direct call of the closure's
// function, inlined in turn. After defunctionalization an apply is a
// dispatch, and an IO action a closure in a constructor (MkIO). The
// optimizer works callee first, so each callee is final, and small, when
// its caller inlines it. One function per form the dispatch meets its
// constructor through, each never inlined into the root:
// - @projected: the result of @greet is projected and applied at once; the
//   projection and the dispatch meet the constant action of one region
//   and the constructor of the other;
// - @branched: the result is applied in each region of a match, after the
//   output the other region does; case of case brings each constructor in;
// - @entered: the result enters a linear position and is used at once
//   before its field is applied; the pair only moves the action in and
//   out, and folds away;
// - @chained: a call whose result is applied, and that result applied
//   again, through @mk and @curry to @add.
// No call of any of them is left.
// Each fold keeps the program's meaning: on every one-byte input, 0 taking
// the constant action and the rest @put's, the optimized program prints
// what the program as written does (%differential).
!Unit = !idr.data<"Unit">
!IORes = !idr.data<"IORes">
!IO = !idr.data<"IO">
#types = #idr.types<
  "IO" = plain [@MkIO(!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)],
  "IORes" = plain [@MkIORes(!Unit, !idr.world)],
  "Unit" = plain [@MkUnit()]
>
idr.program @"known-constructor" root(@Main.main) stage(higher) types #types {
  idr.func @put(%n: i64, %w: !idr.world) -> !IORes attributes {total} {
    %w1 = idr.io.put_sint %n, %w : i64
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
  idr.func @projected(%n: i64, %w: !idr.world) -> !IORes attributes {no_inline} {
    %a = idr.call @greet(%n) : (i64) -> !IO
    %f = idr.field %a : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %r = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r : !IORes
  }
  idr.func @branched(%n: i64, %w: !idr.world) -> !IORes attributes {no_inline} {
    %a = idr.call @greet(%n) : (i64) -> !IO
    %r = idr.match_lit %n : i64 -> (!IORes) {
    case 0 {
      %f = idr.field %a : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
      %s = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
      idr.yield %s : !IORes
    }
    default(%d: i64) {
      %w1 = idr.io.put_sint %n, %w : i64
      %f = idr.field %a : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
      %s = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
      idr.yield %s : !IORes
    }
    }
    return %r : !IORes
  }
  idr.func @entered(%n: i64, %w: !idr.world) -> !IORes attributes {no_inline} {
    %io = idr.call @greet(%n) : (i64) -> !IO
    %in = idr.lin.enter %io : !idr.lin<!IO>
    %out = idr.lin.use %in : !idr.lin<!IO>
    %f = idr.field %out : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %r = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r : !IORes
  }
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @curry(%a: i64, %x: i64) -> !idr.fn<(i64) -> i64> attributes {total} {
    %s = arith.addi %a, %x : i64
    %f = idr.closure @add(%s) : (i64) -> !idr.fn<(i64) -> i64>
    return %f : !idr.fn<(i64) -> i64>
  }
  idr.func @mk(%a: i64) -> !idr.fn<(i64) -> !idr.fn<(i64) -> i64>> attributes {total} {
    %f = idr.closure @curry(%a) : (i64) -> !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
    return %f : !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
  }
  idr.func @chained(%n: i64) -> i64 attributes {no_inline} {
    %f = idr.call @mk(%n) : (i64) -> !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
    %g = idr.apply %f(%n) : !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
    %r = idr.apply %g(%n) : !idr.fn<(i64) -> i64>
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !IORes {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %r1 = idr.call @projected(%n, %w1) : (i64, !idr.world) -> !IORes
    %w2 = idr.field %r1 : !IORes @MkIORes[1] -> !idr.world
    %r2 = idr.call @branched(%n, %w2) : (i64, !idr.world) -> !IORes
    %w3 = idr.field %r2 : !IORes @MkIORes[1] -> !idr.world
    %r3 = idr.call @entered(%n, %w3) : (i64, !idr.world) -> !IORes
    %w4 = idr.field %r3 : !IORes @MkIORes[1] -> !idr.world
    %x = idr.call @chained(%n) : (i64) -> i64
    %w5 = idr.io.put_sint %x, %w4 : i64
    %u = idr.con !Unit @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !Unit, %w5 : !idr.world)
    return %r : !IORes
  }
}
