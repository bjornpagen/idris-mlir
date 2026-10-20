// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-cells),idr-rc-stack,idr-rc-grades))' -o %t.plain.mlir
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-frames,idr.func(idr-rc-cells),idr-rc-stack,idr-rc-grades))' -o %t.framed.mlir
// RUN: %status 1 diff %t.plain.mlir %t.framed.mlir
// RUN: %differential %t.plain.mlir %t.framed.mlir
// A frame pushed by a call of one member is popped by another's return.
// @f runs @g's closure, not in tail position, and adds its argument to
// what it gives: that is the frame, which holds the argument. @g goes on
// in @h, and @h in @f, by tail calls, so when @f's last level returns 0
// the frame on top was pushed by the call of @g, and it is @f's resume
// that pops it. Each resume runs every frame whose value is of its result
// type, whichever member pushed it; a frame resumed only by its callee's
// resume ran no rest there (it was unreachable), and the program printed
// garbage or crashed. The root prints f n, which is n(n+1)/2, for the byte
// n it reads. Both programs are compiled from the stage idr-rc-grades
// leaves (with the cells it reads made explicit), past the optimizer,
// which would otherwise run again on the frames.
// STDIN: \0000
// STDIN: \0001
// STDIN: \0007
// STDIN: \0144
!fn = !idr.data<"fn", closures [@g() label @g, @h() label @h]>
idr.program @"frames-resume-by-type" root(@root) stage(first) {
  idr.func @f(%n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    default(%m: i64) {
      %v = idr.call @g(%m) : (i64) -> i64
      %s = arith.addi %v, %m : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @g(%n: i64) -> i64 attributes {total} {
    %one = arith.constant 1 : i64
    %p = arith.subi %n, %one : i64
    %r = idr.call @h(%p) : (i64) -> i64
    return %r : i64
  }
  idr.func @h(%n: i64) -> i64 attributes {total} {
    %r = idr.call @f(%n) : (i64) -> i64
    return %r : i64
  }
  // The closures @g and @h are labels of: built, never run.
  idr.func @labels() -> !fn attributes {total} {
    %c = idr.con !fn @g()
    return %c : !fn
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %n = arith.extui %ch : i32 to i64
    %r = idr.call @f(%n) : (i64) -> i64
    %s = idr.str.show_sint %r : i64
    %w1 = idr.io.put_str %s, %w0
    return %w1 : !idr.world
  }
}
