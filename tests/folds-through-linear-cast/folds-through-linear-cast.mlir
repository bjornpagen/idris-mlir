// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main})' -verify-diagnostics -o /dev/null
// A value cast into a linear position is the value it was, at another
// grade: what is known of the value is known through the cast. After the
// first stage nothing in @main computes from constants alone but exp,
// which no fold computes, and whose operand each program makes a constant
// only if the value was read through its cast. In the first program a
// constructor whose field is a line read at run time, so no constant, is
// widened to its family and cast into a linear position, and a match on
// the cast runs that constructor's case, which yields 3.0, and not the
// other's, which yields a byte read at run time. In the second the field
// such a constructor was given, 3, is read back through its cast. In the
// third a constructor of constants, a constant, is cast into a linear
// position, where no constant stands, and its field, 3, is read off the
// constant the cast is.
#E = #idr.family<"Either" [] {
    @Left (!idr.str)
    @Right (!idr.str)
  }>
!E = !idr.data<#E>
!Left = !idr.data<#E @Left>
!E1 = !idr.graded<once, counted, !idr.data<#E>>
!Left1 = !idr.graded<once, counted, !idr.data<#E @Left>>
!Right1 = !idr.graded<once, counted, !idr.data<#E @Right>>
!Str = !idr.graded<many, static, !idr.str>
idr.program @matched root(@main) stage(first) {
  idr.func @main() {
    %line = idr.io.get_line : () -> !idr.str
    %byte = idr.io.get_byte : () -> i32
    %read = arith.uitofp %byte : i32 to f64
    %left = idr.data.con(%line : !idr.str) : !Left
    %either = idr.data.reindex %left : !Left to !E
    %once = idr.lin.cast %either : !E -> !E1
    %r = idr.data.match %once : !E1 -> (f64) {
    case @Left(%l: !Left1) {
      %three = arith.constant 3.0 : f64
      idr.yield %three : f64
    }
    case @Right(%x: !Right1) {
      idr.yield %read : f64
    }
    }
    // expected-error @below {{expected folded: }}
    %e = math.exp %r : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}

// -----

#P = #idr.family<"P" [] {
    @MkP (i64, !idr.str)
  }>
!MkP = !idr.data<#P @MkP>
!MkP1 = !idr.graded<once, counted, !idr.data<#P @MkP>>
!Str = !idr.graded<many, static, !idr.str>
idr.program @given root(@main) stage(first) {
  idr.func @main() {
    %line = idr.io.get_line : () -> !idr.str
    %three = arith.constant 3 : i64
    %p = idr.data.con(%three : i64, %line : !idr.str) : !MkP
    %once = idr.lin.cast %p : !MkP -> !MkP1
    %first = idr.data.field %once[0] : !MkP1 -> i64
    %real = arith.sitofp %first : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %real : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}

// -----

#P = #idr.family<"P" [] {
    @MkP (i64, !idr.str)
  }>
!MkPS = !idr.graded<many, static, !idr.data<#P @MkP>>
!MkP1 = !idr.graded<once, static, !idr.data<#P @MkP>>
!Str = !idr.graded<many, static, !idr.str>
idr.program @constant root(@main) stage(first) {
  idr.func @main() {
    %x = idr.constant !Str "x"
    %three = arith.constant 3 : i64
    %p = idr.data.con(%three : i64, %x : !Str) : !MkPS
    %once = idr.lin.cast %p : !MkPS -> !MkP1
    %first = idr.data.field %once[0] : !MkP1 -> i64
    %real = arith.sitofp %first : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %real : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}
