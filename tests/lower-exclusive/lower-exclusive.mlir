// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,straight-line=@exclusive,calls-only=@exclusive:[],calls=@owned:@idris_rt_inc,calls=@owned:@idris_rt_cell' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// A take of an exclusive value moves its fields out with no count test:
// the cell is the token. A recycle of an exclusive token is its cell, with
// no null test and no allocation. So the exclusive function runs one path
// and asks the runtime for nothing. A take of an owned value tests its
// count, giving a field that moves on a reference of its own when the
// cell is shared, and a recycle of its token tests for null, allocating a
// cell when it is. Each path keeps the values: the root, of the byte x it
// reads, gives @exclusive the cell [x] and reads x + 1 at its head; gives
// @owned a second reference to an owned [x] and reads x + 1 at the head of
// the new cell, and x at the head of the one it shared; then gives @owned
// that cell, exclusive again, and reads x + 2 at its head. The program,
// lowered and as written, prints those four, as the reference at the end
// (REF), with no list, does (%differential, on 0, 255 and the end of
// input).
// STDIN: \0000
// STDIN: \0377
// STDIN:
!L = !idr.data<"L">
#types = #idr.types<
  "L" = list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]
>
idr.program @exclusive root(@Prog.main) stage(owned) types #types {
  idr.func @exclusive(%l: !idr.excl<!idr.box<!L>>, %x: i64) -> !idr.excl<!idr.box<!L>> {
    %w:3 = idr.take %l : !idr.excl<!idr.box<!L>> @C -> (!idr.excl<!idr.token>, i64, !idr.excl<!idr.box<!L>>)
    %k = idr.cell.recycle %w#0 : !idr.excl<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
    %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%x : i64, %w#2 : !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
    return %c : !idr.excl<!idr.box<!L>>
  }
  idr.func @owned(%l: !idr.own<!idr.box<!L>>, %x: i64) -> !idr.own<!idr.box<!L>> {
    %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
    %k = idr.cell.recycle %w#0 : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
    %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%x : i64, %w#2 : !idr.own<!idr.box<!L>>)
    return %c : !idr.own<!idr.box<!L>>
  }
  idr.func @head(%l: !idr.q<many, borrow, !idr.box<!L>>) -> i64 {
    %r = idr.match %l : !idr.q<many, borrow, !idr.box<!L>> -> (i64) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.yield %h : i64
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
      %none = arith.constant -1 : i64
      idr.yield %none : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %y = arith.addi %x, %one : i64
    %z = arith.addi %x, %two : i64
    %en = idr.con !idr.excl<!idr.box<!L>> @N()
    %ek = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    %e = idr.cell.init %ek : !idr.cell<!idr.box<!L>, @C> (%x : i64, %en : !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
    %e2 = idr.call @exclusive(%e, %y) : (!idr.excl<!idr.box<!L>>, i64) -> !idr.excl<!idr.box<!L>>
    %eb = idr.borrow %e2 : !idr.excl<!idr.box<!L>>
    %a = idr.call @head(%eb) : (!idr.q<many, borrow, !idr.box<!L>>) -> i64
    idr.drop %e2 : !idr.excl<!idr.box<!L>>
    %on = idr.con !idr.own<!idr.box<!L>> @N()
    %ok = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    %o = idr.cell.init %ok : !idr.cell<!idr.box<!L>, @C> (%x : i64, %on : !idr.own<!idr.box<!L>>)
    %ob = idr.borrow %o : !idr.own<!idr.box<!L>>
    %o2 = idr.dup %ob : !idr.q<many, borrow, !idr.box<!L>>
    %r = idr.call @owned(%o2, %y) : (!idr.own<!idr.box<!L>>, i64) -> !idr.own<!idr.box<!L>>
    %rb = idr.borrow %r : !idr.own<!idr.box<!L>>
    %b = idr.call @head(%rb) : (!idr.q<many, borrow, !idr.box<!L>>) -> i64
    idr.drop %r : !idr.own<!idr.box<!L>>
    %ob2 = idr.borrow %o : !idr.own<!idr.box<!L>>
    %d = idr.call @head(%ob2) : (!idr.q<many, borrow, !idr.box<!L>>) -> i64
    %s = idr.call @owned(%o, %z) : (!idr.own<!idr.box<!L>>, i64) -> !idr.own<!idr.box<!L>>
    %sb = idr.borrow %s : !idr.own<!idr.box<!L>>
    %f = idr.call @head(%sb) : (!idr.q<many, borrow, !idr.box<!L>>) -> i64
    idr.drop %s : !idr.own<!idr.box<!L>>
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_sint %a, %w1 : i64
    %w3 = idr.io.put_char %nl, %w2
    %w4 = idr.io.put_sint %b, %w3 : i64
    %w5 = idr.io.put_char %nl, %w4
    %w6 = idr.io.put_sint %d, %w5 : i64
    %w7 = idr.io.put_char %nl, %w6
    %w8 = idr.io.put_sint %f, %w7 : i64
    %w9 = idr.io.put_char %nl, %w8
    return %w9 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %x = arith.extui %c : i32 to i64
// REF:     %one = arith.constant 1 : i64
// REF:     %two = arith.constant 2 : i64
// REF:     %y = arith.addi %x, %one : i64
// REF:     %z = arith.addi %x, %two : i64
// REF:     %nl = arith.constant 10 : i32
// REF:     %w2 = idr.io.put_sint %y, %w1 : i64
// REF:     %w3 = idr.io.put_char %nl, %w2
// REF:     %w4 = idr.io.put_sint %y, %w3 : i64
// REF:     %w5 = idr.io.put_char %nl, %w4
// REF:     %w6 = idr.io.put_sint %x, %w5 : i64
// REF:     %w7 = idr.io.put_char %nl, %w6
// REF:     %w8 = idr.io.put_sint %z, %w7 : i64
// REF:     %w9 = idr.io.put_char %nl, %w8
// REF:     return %w9 : !idr.world
// REF:   }
// REF: }
