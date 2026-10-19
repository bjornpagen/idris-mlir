// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=lowered,reads-nothing=@f,calls-only=@f:[] -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=signature=@f:(i8,i32,i64,i8)->i64' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// S has three constructors, so an i8 tag; B's i32 and C's flattened P
// (i64, i8) get separate slots, so an unboxed sum travels as its tag and
// its slots. A match on it reads each case's fields from those slots, in
// its region, and reads no memory; with no default, the last case is the
// default (Idris proved the others impossible).
// Each case reads its own slots: the root builds A, B of the byte it reads
// less 128 (a negative Int32 below 128, which the case extends with its
// sign) and C of a P whose i64 is the byte times 2^40, and the program,
// lowered and as written, prints what @f gives for each, 0, the byte less
// 128 and the byte times 2^40, as the reference at the end (REF), with no
// sum, does (%differential, on 0, 127, 128, 255 and the end of input).
// STDIN: \0000
// STDIN: \0177
// STDIN: \0200
// STDIN: \0377
// STDIN:
!P = !idr.data<"P", plain [@MkP(i64, i8)]>
!S = !idr.data<"S", plain [@A(), @B(i32), @C(!P)]>
idr.program @"data-layout" root(@Prog.main) stage(owned) {
  idr.func @f(%s: !S) -> i64 {
    %r = idr.match %s : !S -> (i64) {
    case @A() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @B(%x: i32) {
      %y = arith.extsi %x : i32 to i64
      idr.yield %y : i64
    }
    case @C(%p: !P) {
      %z = idr.field %p : !P @MkP[0] -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %k = arith.constant 128 : i32
    %b = arith.subi %c, %k : i32
    %wide = arith.extui %c : i32 to i64
    %forty = arith.constant 40 : i64
    %high = arith.shli %wide, %forty : i64
    %low = arith.trunci %c : i32 to i8
    %sa = idr.con !S @A()
    %sb = idr.con !S @B(%b : i32)
    %p = idr.con !P @MkP(%high : i64, %low : i8)
    %sc = idr.con !S @C(%p : !P)
    %ra = idr.call @f(%sa) : (!S) -> i64
    %rb = idr.call @f(%sb) : (!S) -> i64
    %rc = idr.call @f(%sc) : (!S) -> i64
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_sint %ra, %w1 : i64
    %w3 = idr.io.put_char %nl, %w2
    %w4 = idr.io.put_sint %rb, %w3 : i64
    %w5 = idr.io.put_char %nl, %w4
    %w6 = idr.io.put_sint %rc, %w5 : i64
    %w7 = idr.io.put_char %nl, %w6
    return %w7 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %wide = arith.extui %c : i32 to i64
// REF:     %k = arith.constant 128 : i64
// REF:     %b = arith.subi %wide, %k : i64
// REF:     %forty = arith.constant 40 : i64
// REF:     %high = arith.shli %wide, %forty : i64
// REF:     %z = arith.constant 0 : i64
// REF:     %nl = arith.constant 10 : i32
// REF:     %w2 = idr.io.put_sint %z, %w1 : i64
// REF:     %w3 = idr.io.put_char %nl, %w2
// REF:     %w4 = idr.io.put_sint %b, %w3 : i64
// REF:     %w5 = idr.io.put_char %nl, %w4
// REF:     %w6 = idr.io.put_sint %high, %w5 : i64
// REF:     %w7 = idr.io.put_char %nl, %w6
// REF:     return %w7 : !idr.world
// REF:   }
// REF: }
