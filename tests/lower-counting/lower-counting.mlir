// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,call-order=@counts:[@idris_rt_inc,@idris_rt_dec,@idris_rt_dec]' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=call-order=@drop:[@idris_rt_dec,@idris_rt_dec,@idris_rt_free_cell],never-calls=@drop:@idris_rt_inc,never-calls=@static:@idris_rt_inc,calls=@rebuild:@idris_rt_cell,never-calls=@rebuild:@idris_rt_free_cell' -o /dev/null
// The counting ops call the runtime on each counted component: a string's
// pointer, a big's word (as a pointer), each counted slot of a sum, in the
// order the program counts. A take of a box yields its cell when it is
// exclusive, and otherwise gives each field that moves on a reference and
// drops the box's; a field nothing wants (its one use an idr.drop) dies
// with the box: dropped where the box is exclusive, untouched where it is
// shared, so no reference is taken for it; a token that is dropped has its
// memory freed. A reference to static data (a constant box, a constant
// string) counts nothing: static data holds no count. A recycled cell is
// the token's, or a new cell when it is null, and never frees it.
// Each path runs, and keeps the values: the root builds [x, x + 1] of the
// byte x it reads, takes it apart by @drop while a second reference holds
// it (shared), rebuilds it by @rebuild once that reference is gone
// (exclusive, its cell recycled), reads its head and takes it apart by
// @drop again (exclusive, its cell freed); then @static's list and string
// for x (N for 0, [x] otherwise), and @counts' string. The program,
// lowered and as written, prints x, x, x, @static's head (-1 for N) and
// its string, and @counts' string, as the reference at the end (REF),
// with no list, does (%differential, on 0, 1, 255 and the end of input).
// STDIN: \0000
// STDIN: \0001
// STDIN: \0377
// STDIN:
!L = !idr.data<"L">
!S = !idr.data<"S">
#types = #idr.types<
  "L" = list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons],
  "S" = plain [@A(!idr.str), @B(i64)]
>
idr.program @counting root(@Prog.main) stage(owned) types #types {
  idr.func @counts(%s: !idr.q<many, borrow, !idr.str>, %d: !idr.own<!S>, %b: !idr.own<!idr.big>) -> !idr.own<!idr.str> {
    %o = idr.dup %s : !idr.q<many, borrow, !idr.str>
    idr.drop %d : !idr.own<!S>
    idr.drop %b : !idr.own<!idr.big>
    return %o : !idr.own<!idr.str>
  }
  idr.func @unused(%x: i64) -> !idr.own<!S> {
    %d = idr.con !idr.own<!S> @B(%x : i64)
    return %d : !idr.own<!S>
  }
  idr.func @drop(%l: !idr.own<!idr.box<!L>>) -> i64 {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (i64) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      idr.drop %w#2 : !idr.own<!idr.box<!L>>
      idr.drop %w#0 : !idr.own<!idr.token>
      idr.yield %h : i64
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.drop %l : !idr.own<!idr.box<!L>>
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @static(%x: i64) -> (!idr.own<!idr.box<!L>>, !idr.own<!idr.str>) {
    %n = idr.constant !idr.q<many, borrow, !idr.box<!L>> #idr.con<!L, @N, []>
    %s = idr.constant !idr.q<many, borrow, !idr.str> "static"
    %r = idr.match_lit %x : i64 -> (!idr.own<!idr.box<!L>>) {
    case 0 {
      %o = idr.dup %n : !idr.q<many, borrow, !idr.box<!L>>
      idr.yield %o : !idr.own<!idr.box<!L>>
    }
    default(%d: i64) {
      %o = idr.dup %n : !idr.q<many, borrow, !idr.box<!L>>
      %k = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
      %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%x : i64, %o : !idr.own<!idr.box<!L>>)
      idr.yield %c : !idr.own<!idr.box<!L>>
    }
    }
    %t = idr.dup %s : !idr.q<many, borrow, !idr.str>
    return %r, %t : !idr.own<!idr.box<!L>>, !idr.own<!idr.str>
  }
  idr.func @rebuild(%l: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (!idr.own<!idr.box<!L>>) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      %k = idr.cell.recycle %w#0 : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
      %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%w#1 : i64, %w#2 : !idr.own<!idr.box<!L>>)
      idr.yield %c : !idr.own<!idr.box<!L>>
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.yield %l : !idr.own<!idr.box<!L>>
    }
    }
    return %r : !idr.own<!idr.box<!L>>
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    %nil = idr.con !idr.own<!idr.box<!L>> @N()
    %kt = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    %t = idr.cell.init %kt : !idr.cell<!idr.box<!L>, @C> (%y : i64, %nil : !idr.own<!idr.box<!L>>)
    %kl = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    %l = idr.cell.init %kl : !idr.cell<!idr.box<!L>, @C> (%x : i64, %t : !idr.own<!idr.box<!L>>)
    %lb = idr.borrow %l : !idr.own<!idr.box<!L>>
    %l2 = idr.dup %lb : !idr.q<many, borrow, !idr.box<!L>>
    %a = idr.call @drop(%l2) : (!idr.own<!idr.box<!L>>) -> i64
    %r = idr.call @rebuild(%l) : (!idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>>
    %rb = idr.borrow %r : !idr.own<!idr.box<!L>>
    %h = idr.match %rb : !idr.q<many, borrow, !idr.box<!L>> -> (i64) {
    case @C(%hd: i64, %tl: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.yield %hd : i64
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
      %none = arith.constant -1 : i64
      idr.yield %none : i64
    }
    }
    %b = idr.call @drop(%r) : (!idr.own<!idr.box<!L>>) -> i64
    %s:2 = idr.call @static(%x) : (i64) -> (!idr.own<!idr.box<!L>>, !idr.own<!idr.str>)
    %sb = idr.borrow %s#0 : !idr.own<!idr.box<!L>>
    %k = idr.match %sb : !idr.q<many, borrow, !idr.box<!L>> -> (i64) {
    case @C(%hd: i64, %tl: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.yield %hd : i64
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
      %none = arith.constant -1 : i64
      idr.yield %none : i64
    }
    }
    idr.drop %s#0 : !idr.own<!idr.box<!L>>
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_sint %a, %w1 : i64
    %w3 = idr.io.put_char %nl, %w2
    %w4 = idr.io.put_sint %h, %w3 : i64
    %w5 = idr.io.put_char %nl, %w4
    %w6 = idr.io.put_sint %b, %w5 : i64
    %w7 = idr.io.put_char %nl, %w6
    %w8 = idr.io.put_sint %k, %w7 : i64
    %w9 = idr.io.put_char %nl, %w8
    %st = idr.borrow %s#1 : !idr.own<!idr.str>
    %w10 = idr.io.put_str borrow %st, %w9
    %w11 = idr.io.put_char %nl, %w10
    idr.drop %s#1 : !idr.own<!idr.str>
    %word = idr.constant !idr.q<many, borrow, !idr.str> "counted"
    %u = idr.call @unused(%x) : (i64) -> !idr.own<!S>
    %five = idr.constant !idr.q<many, borrow, !idr.big> #idr.big<5>
    %g = idr.dup %five : !idr.q<many, borrow, !idr.big>
    %o = idr.call @counts(%word, %u, %g) : (!idr.q<many, borrow, !idr.str>, !idr.own<!S>, !idr.own<!idr.big>) -> !idr.own<!idr.str>
    %ob = idr.borrow %o : !idr.own<!idr.str>
    %w12 = idr.io.put_str borrow %ob, %w11
    %w13 = idr.io.put_char %nl, %w12
    idr.drop %o : !idr.own<!idr.str>
    return %w13 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %x = arith.extui %c : i32 to i64
// REF:     %zero = arith.constant 0 : i32
// REF:     %none = arith.cmpi eq, %c, %zero : i32
// REF:     %m = arith.constant -1 : i64
// REF:     %k = arith.select %none, %m, %x : i64
// REF:     %nl = arith.constant 10 : i32
// REF:     %w2 = idr.io.put_sint %x, %w1 : i64
// REF:     %w3 = idr.io.put_char %nl, %w2
// REF:     %w4 = idr.io.put_sint %x, %w3 : i64
// REF:     %w5 = idr.io.put_char %nl, %w4
// REF:     %w6 = idr.io.put_sint %x, %w5 : i64
// REF:     %w7 = idr.io.put_char %nl, %w6
// REF:     %w8 = idr.io.put_sint %k, %w7 : i64
// REF:     %w9 = idr.io.put_char %nl, %w8
// REF:     %s = arith.constant 115 : i32
// REF:     %t = arith.constant 116 : i32
// REF:     %a = arith.constant 97 : i32
// REF:     %i = arith.constant 105 : i32
// REF:     %cc = arith.constant 99 : i32
// REF:     %o = arith.constant 111 : i32
// REF:     %u = arith.constant 117 : i32
// REF:     %n = arith.constant 110 : i32
// REF:     %e = arith.constant 101 : i32
// REF:     %d = arith.constant 100 : i32
// REF:     %w10 = idr.io.put_char %s, %w9
// REF:     %w11 = idr.io.put_char %t, %w10
// REF:     %w12 = idr.io.put_char %a, %w11
// REF:     %w13 = idr.io.put_char %t, %w12
// REF:     %w14 = idr.io.put_char %i, %w13
// REF:     %w15 = idr.io.put_char %cc, %w14
// REF:     %w16 = idr.io.put_char %nl, %w15
// REF:     %w17 = idr.io.put_char %cc, %w16
// REF:     %w18 = idr.io.put_char %o, %w17
// REF:     %w19 = idr.io.put_char %u, %w18
// REF:     %w20 = idr.io.put_char %n, %w19
// REF:     %w21 = idr.io.put_char %t, %w20
// REF:     %w22 = idr.io.put_char %e, %w21
// REF:     %w23 = idr.io.put_char %d, %w22
// REF:     %w24 = idr.io.put_char %nl, %w23
// REF:     return %w24 : !idr.world
// REF:   }
// REF: }
