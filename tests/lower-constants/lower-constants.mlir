// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,calls-only=@values:[]' -o /dev/null
// A constant of a string, a small big or a box is static data, and an
// unboxed constant is its components: a constant costs nothing at run
// time, no runtime call makes one, and a reference to one counts nothing.
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
  idr.func @Prog.main() -> i64 {
    %v:5 = idr.call @values() : () -> (!idr.own<!idr.str>, !idr.own<!idr.str>, !idr.own<!idr.big>,
                                        !idr.own<!idr.box<!List>>, !Num)
    idr.drop %v#0 : !idr.own<!idr.str>
    idr.drop %v#1 : !idr.own<!idr.str>
    idr.drop %v#2 : !idr.own<!idr.big>
    idr.drop %v#3 : !idr.own<!idr.box<!List>>
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
