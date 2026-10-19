// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
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
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
!S = !idr.data<"S", plain [@A(!idr.str), @B(i64)]>
idr.program @counting root(@Prog.main) stage(owned) {
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
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
