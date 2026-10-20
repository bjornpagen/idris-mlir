// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=calls=@Main.main:@grow,specialized-once=@grow,calls=@Main.main:@float,specialized-once=@float,calls=@Main.main:@spell,specialized-once=@spell,calls=@Main.main:@down,specialized-once=@down -o /dev/null
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=reaches=@Main.main:@step,specialized-once=@step -o /dev/null
// A recursion whose argument the caller knows but the callee changes at
// every call asks for a specialization of the next step from the last.
// Each request is kept with the requests before it. One whose key has the
// shape of an earlier one but other scalars (an integer, a Double, a
// String's characters) is lifted: those scalars become parameters of one
// copy, which every later step then reaches. One whose key has more
// structure than an earlier one is refused, and its call stays a call. So
// the optimizer ends:
//   - @grow conses onto a list from Nil: [Cons 0 Nil] grows [Nil] and is
//     refused;
//   - @float steps a Double in a Maybe from Just 0.0, @spell reverses a
//     String in a Maybe at its length, and @down counts an Int down in a
//     Maybe from Just 1000000: the second key of each is lifted to Just _;
//   - @loopIO is an action that prints a Double and runs itself on the
//     next: once defunctionalized, the Double is a capture of @step's
//     closure, a field of a constructor, and lifted the same way.
// None of the functions ends, which the optimizer does not ask: none is
// total.
!L = !idr.data<"L">
!MaybeD = !idr.data<"MaybeD">
!MaybeS = !idr.data<"MaybeS">
!MaybeI = !idr.data<"MaybeI">
!Unit = !idr.data<"Unit">
!IORes = !idr.data<"IORes">
#types = #idr.types<
  "IORes" = plain [@MkIORes(!Unit, !idr.world)],
  "L" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons],
  "MaybeD" = plain [@Nothing(), @Just(f64)],
  "MaybeI" = plain [@NoInt(), @AnInt(i64)],
  "MaybeS" = plain [@None(), @Some(!idr.str)],
  "Unit" = plain [@MkUnit()]
>
idr.program @"specialize-ends" root(@Main.main) stage(higher) types #types {
  idr.func @grow(%xs: !idr.box<!L>) -> i64 {
    %z = arith.constant 0 : i64
    %c = idr.con !idr.box<!L> @Cons(%z : i64, %xs : !idr.box<!L>)
    %r = idr.call @grow(%c) : (!idr.box<!L>) -> i64
    return %r : i64
  } loc("grow")
  idr.func @float(%m: !MaybeD) -> i64 {
    %r = idr.match %m : !MaybeD -> (i64) {
    case @Nothing() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Just(%x: f64) {
      %one = arith.constant 1.0 : f64
      %y = arith.addf %x, %one : f64
      %j = idr.con !MaybeD @Just(%y : f64)
      %s = idr.call @float(%j) : (!MaybeD) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  } loc("float")
  idr.func @spell(%m: !MaybeS) -> i64 {
    %r = idr.match %m : !MaybeS -> (i64) {
    case @None() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Some(%s: !idr.str) {
      %t = idr.str.reverse %s
      %j = idr.con !MaybeS @Some(%t : !idr.str)
      %v = idr.call @spell(%j) : (!MaybeS) -> i64
      idr.yield %v : i64
    }
    }
    return %r : i64
  } loc("spell")
  idr.func @down(%m: !MaybeI) -> i64 {
    %r = idr.match %m : !MaybeI -> (i64) {
    case @NoInt() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @AnInt(%n: i64) {
      %one = arith.constant 1 : i64
      %k = arith.subi %n, %one : i64
      %j = idr.con !MaybeI @AnInt(%k : i64)
      %v = idr.call @down(%j) : (!MaybeI) -> i64
      idr.yield %v : i64
    }
    }
    return %r : i64
  } loc("down")
  // print x, then the action of x + 1.0.
  idr.func @step(%x: f64, %w: !idr.world) -> !IORes {
    %w1 = idr.io.put_double %x, %w
    %one = arith.constant 1.0 : f64
    %y = arith.addf %x, %one : f64
    %k = idr.call @loopIO(%y) : (f64) -> !idr.fn<(!idr.world) -> (!IORes)>
    %r = idr.apply %k(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r : !IORes
  } loc("step")
  idr.func @loopIO(%x: f64) -> !idr.fn<(!idr.world) -> (!IORes)> {
    %k = idr.closure @step(%x) : (f64) -> !idr.fn<(!idr.world) -> (!IORes)>
    return %k : !idr.fn<(!idr.world) -> (!IORes)>
  } loc("loopIO")
  idr.func @Main.main(%w: !idr.world) -> !IORes {
    %nil = idr.constant !idr.box<!L> #idr.con<!L, @Nil, []>
    %a = idr.call @grow(%nil) : (!idr.box<!L>) -> i64
    %zero = arith.constant 0.0 : f64
    %jd = idr.con !MaybeD @Just(%zero : f64)
    %b = idr.call @float(%jd) : (!MaybeD) -> i64
    %ab = idr.constant !idr.str "ab"
    %js = idr.con !MaybeS @Some(%ab : !idr.str)
    %c = idr.call @spell(%js) : (!MaybeS) -> i64
    %million = arith.constant 1000000 : i64
    %ji = idr.con !MaybeI @AnInt(%million : i64)
    %d = idr.call @down(%ji) : (!MaybeI) -> i64
    %s1 = arith.addi %a, %b : i64
    %s2 = arith.addi %s1, %c : i64
    %s = arith.addi %s2, %d : i64
    %w1 = idr.io.put_sint %s, %w : i64
    %k = idr.call @loopIO(%zero) : (f64) -> !idr.fn<(!idr.world) -> (!IORes)>
    %r = idr.apply %k(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r : !IORes
  }
}
