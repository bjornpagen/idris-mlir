// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,calls-only=@values:[]' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// A constant of a string, a small big or a box is static data, and an
// unboxed constant is its components: a constant costs nothing at run
// time, no runtime call makes one, and a reference to one counts nothing.
// The static data holds the values: the root prints both strings, the big,
// the list's head and the Double of the sum, and the program, lowered and
// as written, prints what the reference at the end (REF) writes a
// character and a word at a time, with no static data: hé!hé!, -43, 7 and
// 2.5 (%differential, on the one input, none, since it reads none).
// STDIN:
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
!Num = !idr.data<"Num", plain [@I(i64), @D(f64)]>
idr.program @constants root(@Prog.main) stage(owned) {
  idr.func @values() -> (!idr.own<!idr.str>, !idr.own<!idr.str>, !idr.own<!idr.big>,
                         !idr.own<!idr.box<!List>>, !Num) {
    %s1 = idr.constant !idr.q<many, borrow, !idr.str> "h\C3\A9!"
    %s2 = idr.constant !idr.q<many, borrow, !idr.str> "h\C3\A9!"
    %small = idr.constant !idr.q<many, borrow, !idr.big> #idr.big<-43>
    %l = idr.constant !idr.q<many, borrow, !idr.box<!List>> #idr.con<!List, @Cons, [7, #idr.con<!List, @Nil, []>]>
    %n = idr.constant !Num #idr.con<!Num, @D, [2.5 : f64]>
    %o1 = idr.dup %s1 : !idr.q<many, borrow, !idr.str>
    %o2 = idr.dup %s2 : !idr.q<many, borrow, !idr.str>
    %o3 = idr.dup %small : !idr.q<many, borrow, !idr.big>
    %o5 = idr.dup %l : !idr.q<many, borrow, !idr.box<!List>>
    return %o1, %o2, %o3, %o5, %n
        : !idr.own<!idr.str>, !idr.own<!idr.str>, !idr.own<!idr.big>, !idr.own<!idr.box<!List>>, !Num
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %v:5 = idr.call @values() : () -> (!idr.own<!idr.str>, !idr.own<!idr.str>, !idr.own<!idr.big>,
                                        !idr.own<!idr.box<!List>>, !Num)
    %s1 = idr.borrow %v#0 : !idr.own<!idr.str>
    %w1 = idr.io.put_str borrow %s1, %w
    %s2 = idr.borrow %v#1 : !idr.own<!idr.str>
    %w2 = idr.io.put_str borrow %s2, %w1
    %b = idr.borrow %v#2 : !idr.own<!idr.big>
    %t = idr.big.show borrow %b : !idr.own<!idr.str>
    %tb = idr.borrow %t : !idr.own<!idr.str>
    %w3 = idr.io.put_str borrow %tb, %w2
    idr.drop %t : !idr.own<!idr.str>
    %l = idr.borrow %v#3 : !idr.own<!idr.box<!List>>
    %h = idr.match %l : !idr.q<many, borrow, !idr.box<!List>> -> (i64) {
    case @Cons(%x: i64, %tl: !idr.q<many, borrow, !idr.box<!List>>) {
      idr.yield %x : i64
    }
    default(%d: !idr.q<many, borrow, !idr.box<!List>>) {
      %none = arith.constant -1 : i64
      idr.yield %none : i64
    }
    }
    %w4 = idr.io.put_sint %h, %w3 : i64
    %f = idr.match %v#4 : !Num -> (f64) {
    case @I(%i: i64) {
      %g = arith.sitofp %i : i64 to f64
      idr.yield %g : f64
    }
    case @D(%e: f64) {
      idr.yield %e : f64
    }
    }
    %w5 = idr.io.put_double %f, %w4
    idr.drop %v#0 : !idr.own<!idr.str>
    idr.drop %v#1 : !idr.own<!idr.str>
    idr.drop %v#2 : !idr.own<!idr.big>
    idr.drop %v#3 : !idr.own<!idr.box<!List>>
    return %w5 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) {
// REF:   idr.func @word(%w: !idr.world) -> !idr.world {
// REF:     %h = arith.constant 104 : i32
// REF:     %e = arith.constant 233 : i32
// REF:     %x = arith.constant 33 : i32
// REF:     %w1 = idr.io.put_char %h, %w
// REF:     %w2 = idr.io.put_char %e, %w1
// REF:     %w3 = idr.io.put_char %x, %w2
// REF:     return %w3 : !idr.world
// REF:   }
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %w1 = idr.call @word(%w) : (!idr.world) -> !idr.world
// REF:     %w2 = idr.call @word(%w1) : (!idr.world) -> !idr.world
// REF:     %n = arith.constant -43 : i64
// REF:     %w3 = idr.io.put_sint %n, %w2 : i64
// REF:     %s = arith.constant 7 : i64
// REF:     %w4 = idr.io.put_sint %s, %w3 : i64
// REF:     %d = arith.constant 2.5 : f64
// REF:     %w5 = idr.io.put_double %d, %w4
// REF:     return %w5 : !idr.world
// REF:   }
// REF: }
