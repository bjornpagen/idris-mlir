// RUN: idris-mlir-opt %s --sccp --idr-expect=holds=returns=@second:7,reads-no-fields=@second,returns=@seven:7,returns=@first:_,reads-fields=@first -o /dev/null
// RUN: idris-mlir-opt %s --sccp -o %t.sccp.mlir
// RUN: %differential %s %t.sccp.mlir
// SCCP propagates a constructor constant through a call into a private
// function, where the field read of it folds (@second, called only by
// @seven, with a constant). Where a field of the constructor is read at
// run time, its read stays (@first, whose one caller builds it of the byte
// read). The program means the same before SCCP and after, which
// idris-mlir's own pipeline does not run, on the empty input and every
// byte.
!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.program @sccp root(@Prog.main) stage(first) {
  idr.func @second(%p: !P) -> i64 {
    %y = idr.field %p : !P @MkP[1] -> i64
    return %y : i64
  }

  idr.func @seven() -> i64 {
    %a = arith.constant 6 : i64
    %b = arith.constant 7 : i64
    %p = idr.con !P @MkP(%a : i64, %b : i64)
    %r = idr.call @second(%p) : (!P) -> i64
    return %r : i64
  }

  idr.func @first(%p: !P) -> i64 {
    %x = idr.field %p : !P @MkP[0] -> i64
    return %x : i64
  }

  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %b = arith.constant 7 : i64
    %q = idr.con !P @MkP(%x : i64, %b : i64)
    %s = idr.call @first(%q) : (!P) -> i64
    %r = idr.call @seven() : () -> i64
    %w2 = idr.io.put_sint %s, %w1 : i64
    %sp = arith.constant 32 : i32
    %w3 = idr.io.put_char %sp, %w2
    %w4 = idr.io.put_sint %r, %w3 : i64
    return %w4 : !idr.world
  }
}
