// NEEDS-ACCEPTANCE: that each closure over linear captures, now of the linear closure type itself (S41), defunctionalizes and unfolds into the root as before, no closure left.
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// A do block of 16 statements, in the shape Emit gives it: statement k is
// @sk, the thunk `putStr "k" >> rest` that `>>` delays, whose action is
// @bind of @put and of @seq, which forces the thunk of the next statement.
// Defunctionalization makes every action a constructor of a dispatch sum,
// and the optimizer, callee first, folds each dispatch on a known
// constructor into a call and inlines it: the whole block unfolds into the
// root, in order, and no closure is left.
!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!IORes = !idr.data<"IORes", plain [@MkIORes(!Unit, !idr.world)]>
!IO = !idr.data<"IO", plain [@MkIO(!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)]>
idr.program @"do-block" root(@Main.main) stage(higher) {
  idr.func @put(%s: !idr.str, %w: !idr.world) -> !IORes attributes {total} {
    %w1 = idr.io.put_str %s, %w
    %u = idr.con !Unit @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !Unit, %w1 : !idr.world)
    return %r : !IORes
  }
  idr.func @done(%w: !idr.world) -> !IORes attributes {total} {
    %u = idr.con !Unit @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !Unit, %w : !idr.world)
    return %r : !IORes
  }
  // io_bind: runs %a, applies %k to its value and runs the action that gives.
  idr.func @bind(%a: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, %k: !idr.lin<!idr.fn<(!Unit) -> (!IO)>>, %w: !idr.world) -> !IORes attributes {total} {
    %a_use = idr.lin.use %a : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %r = idr.apply %a_use(%w) : !idr.fn<(!idr.world) -> (!IORes)>
    %u = idr.field %r : !IORes @MkIORes[0] -> !Unit
    %w1 = idr.field %r : !IORes @MkIORes[1] -> !idr.world
    %k_use = idr.lin.use %k : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %io = idr.apply %k_use(%u) : !idr.fn<(!Unit) -> (!IO)>
    %f = idr.field %io : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %s = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
    return %s : !IORes
  }
  // The continuation of `>>`: forces the delayed rest of the block.
  idr.func @seq(%rest: !idr.fn<() -> (!IO)>, %u: !Unit) -> !IO attributes {total} {
    %io = idr.apply %rest() : !idr.fn<() -> (!IO)>
    return %io : !IO
  }
  idr.func @s1() -> !IO attributes {total} {
    %str = idr.constant !idr.str "1\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s2() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s2() -> !IO attributes {total} {
    %str = idr.constant !idr.str "2\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s3() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s3() -> !IO attributes {total} {
    %str = idr.constant !idr.str "3\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s4() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s4() -> !IO attributes {total} {
    %str = idr.constant !idr.str "4\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s5() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s5() -> !IO attributes {total} {
    %str = idr.constant !idr.str "5\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s6() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s6() -> !IO attributes {total} {
    %str = idr.constant !idr.str "6\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s7() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s7() -> !IO attributes {total} {
    %str = idr.constant !idr.str "7\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s8() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s8() -> !IO attributes {total} {
    %str = idr.constant !idr.str "8\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s9() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s9() -> !IO attributes {total} {
    %str = idr.constant !idr.str "9\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s10() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s10() -> !IO attributes {total} {
    %str = idr.constant !idr.str "10\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s11() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s11() -> !IO attributes {total} {
    %str = idr.constant !idr.str "11\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s12() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s12() -> !IO attributes {total} {
    %str = idr.constant !idr.str "12\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s13() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s13() -> !IO attributes {total} {
    %str = idr.constant !idr.str "13\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s14() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s14() -> !IO attributes {total} {
    %str = idr.constant !idr.str "14\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s15() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s15() -> !IO attributes {total} {
    %str = idr.constant !idr.str "15\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %t = idr.closure @s16() : () -> !idr.fn<() -> (!IO)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!IO)>) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %c_lin = idr.lin.enter %c : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %c_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @s16() -> !IO attributes {total} {
    %str = idr.constant !idr.str "16\0A"
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!IORes)>
    %d = idr.closure @done() : () -> !idr.fn<(!idr.world) -> (!IORes)>
    %d_lin = idr.lin.enter %d : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %e = idr.con !IO @MkIO(%d_lin : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    %t = idr.closure @const(%e) : (!IO) -> !idr.fn<(!Unit) -> (!IO)>
    %p_lin = idr.lin.enter %p : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %t_lin = idr.lin.enter %t : !idr.lin<!idr.fn<(!Unit) -> (!IO)>>
    %b = idr.closure @bind(%p_lin, %t_lin) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>, !idr.lin<!idr.fn<(!Unit) -> (!IO)>>) -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%b : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    return %io : !IO
  }
  idr.func @const(%io: !IO, %u: !Unit) -> !IO attributes {total} {
    return %io : !IO
  }
  idr.func @Main.main(%w: !idr.world) -> !IORes attributes {total} {
    %io = idr.call @s1() : () -> !IO
    %f = idr.field %io : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %r = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r : !IORes
  }
}
