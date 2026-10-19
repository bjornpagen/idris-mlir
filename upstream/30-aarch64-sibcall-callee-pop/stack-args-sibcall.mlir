// @pops takes `tailcc`, so it pops its incoming stack arguments when it
// returns: ten i64 arguments are two more than the eight registers hold.
// Its call of the C function @idris_rt_handle_is_null is in tail position.
// As a sibling call it would return straight to @main having popped
// nothing, and @main would find its stack pointer 16 bytes below where it
// left it. @main compares the stack pointer before and after the call
// (llvm.intr.stacksave) and exits 0 when it is where it was, 1 otherwise;
// with the stack this far off its own epilogue may as well fault.
//
// Every argument feeds the result and the result feeds the exit status, so
// the optimizer drops no argument and no call. The result is 1 only for
// the null handle, -1, which the sum, 18 when the program is run with no
// arguments, is not; the status 2 it would give is no run's.
module {
  llvm.func @idris_rt_handle_is_null(i64) -> i64
  llvm.func tailcc @pops(%a0: i64, %a1: i64, %a2: i64, %a3: i64, %a4: i64, %a5: i64, %a6: i64, %a7: i64, %a8: i64, %a9: i64) -> i64 attributes {no_inline} {
    %s1 = llvm.add %a0, %a1 : i64
    %s2 = llvm.add %s1, %a2 : i64
    %s3 = llvm.add %s2, %a3 : i64
    %s4 = llvm.add %s3, %a4 : i64
    %s5 = llvm.add %s4, %a5 : i64
    %s6 = llvm.add %s5, %a6 : i64
    %s7 = llvm.add %s6, %a7 : i64
    %s8 = llvm.add %s7, %a8 : i64
    %s9 = llvm.add %s8, %a9 : i64
    %r = llvm.call @idris_rt_handle_is_null(%s9) : (i64) -> i64
    llvm.return %r : i64
  }
  llvm.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    %a = llvm.sext %argc : i32 to i64
    %b = llvm.add %a, %a : i64
    %c = llvm.mul %a, %b : i64
    %d = llvm.sub %c, %a : i64
    %e = llvm.xor %d, %b : i64
    %before = llvm.intr.stacksave : !llvm.ptr
    %r = llvm.call tailcc @pops(%a, %b, %c, %d, %e, %a, %b, %c, %d, %e) : (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64) -> i64
    %after = llvm.intr.stacksave : !llvm.ptr
    %same = llvm.icmp "eq" %before, %after : !llvm.ptr
    %zero = llvm.mlir.constant(0 : i32) : i32
    %one = llvm.mlir.constant(1 : i32) : i32
    %two = llvm.mlir.constant(2 : i32) : i32
    %null = llvm.mlir.constant(1 : i64) : i64
    %isNull = llvm.icmp "eq" %r, %null : i64
    %kept = llvm.select %isNull, %two, %zero : i1, i32
    %status = llvm.select %same, %kept, %one : i1, i32
    llvm.return %status : i32
  }
}
