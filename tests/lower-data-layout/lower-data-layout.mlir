// RUN: idris-mlir-opt %s --idr-lower --idr-expect=holds=lowered,reads-nothing=@f,calls-only=@f:[] -o /dev/null
// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=signature=@f:(i8,i32,i64,i8)->i64' -o /dev/null
// S has three constructors, so an i8 tag; B's i32 and C's flattened P
// (i64, i8) get separate slots, so an unboxed sum travels as its tag and
// its slots. A match on it reads each case's fields from those slots, in
// its region, and reads no memory; with no default, the last case is the
// default (Idris proved the others impossible).
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
  idr.func @Prog.main() -> i64 {
    %c5 = arith.constant 5 : i32
    %s = idr.con !S @B(%c5 : i32)
    %r = idr.call @f(%s) : (!S) -> i64
    return %r : i64
  }
}
