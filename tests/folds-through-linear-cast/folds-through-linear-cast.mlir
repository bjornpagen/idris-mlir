// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main})' -verify-diagnostics -o /dev/null
// A value cast into a linear position is the value it was, at another
// grade: what is known of the value is known through the cast. After the
// first stage nothing in @main computes from constants alone but exp,
// which no fold computes, and whose operand each of the first five
// programs makes a constant only if the value was read through its cast.
// In the first program a constructor whose field is a line read at run
// time, so no constant, is widened to its family and cast into a linear
// position, and a match on the cast runs that constructor's case, which
// yields 3.0, and not the other's, which yields a byte read at run time.
// In the second the field such a constructor was given, 3, is read back
// through its cast. In the third a constructor of constants, a constant,
// is cast into a linear position, where no constant stands, and its
// field, 3, is read off the constant the cast is. In the fourth a memo
// cell built of 3 is cast out of its linear position, and its field,
// read in place since a force could rewrite it, is the 3 it was given,
// read through the cast. In the fifth a callee returns 2.0 and 3, each
// cast into the one use a function's result has, and the caller casts
// each out of it again: each is the constant the callee returns. In the
// sixth a memo cell built of a byte read at run time is cast out of its
// linear position and forced through the cast, then matched: the force
// rewrote the cell's state, so the constructor that built it no longer
// says its case, and the match is left to run whichever case the cell is
// in; exp's operand is 1.0 or the forced value, no constant, and nothing
// is reported.
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

// -----

#Lazy = #idr.family<"Lazy" memo [] {
    @single fn @single (i64)
  } forced (i64)>
!Single1 = !idr.graded<once, counted, !idr.data<#Lazy @single>>
!Single = !idr.graded<many, counted, !idr.data<#Lazy @single>>
!Str = !idr.graded<many, static, !idr.str>
idr.program @memoField root(@main) stage(first) {
  idr.func @single(%n: i64) -> i64 {
    idr.return %n : i64
  }
  idr.func @main() {
    %three = arith.constant 3 : i64
    %cell = idr.data.con(%three : i64) : !Single1
    %many = idr.lin.cast %cell : !Single1 -> !Single
    %n = idr.data.field %many[0] : !Single -> i64
    %real = arith.sitofp %n : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %real : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}

// -----

!F1 = !idr.graded<once, f64>
!I1 = !idr.graded<once, i64>
!Str = !idr.graded<many, static, !idr.str>
idr.program @returned root(@main) stage(first) {
  idr.func @two() -> (!F1, !I1) {
    %again:2 = idr.call @two() : () -> (!F1, !I1)
    %a = arith.constant 2.0 : f64
    %b = arith.constant 3 : i64
    %a1 = idr.lin.cast %a : f64 -> !F1
    %b1 = idr.lin.cast %b : i64 -> !I1
    idr.return %a1, %b1 : !F1, !I1
  }
  idr.func @main() {
    %r:2 = idr.call @two() : () -> (!F1, !I1)
    %x = idr.lin.cast %r#0 : !F1 -> f64
    %y = idr.lin.cast %r#1 : !I1 -> i64
    %real = arith.sitofp %y : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %x : f64
    // expected-error @below {{expected folded: }}
    %f = math.exp %real : f64
    %eText = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %eText : (!Str) -> ()
    %fText = idr.str.show_double %f : (f64) -> !Str
    idr.io.put_str %fText : (!Str) -> ()
    idr.return
  }
}

// -----

#Lazy = #idr.family<"Lazy" memo [] {
    @single fn @single (i64)
  } forced (i64)>
!Single1 = !idr.graded<once, counted, !idr.data<#Lazy @single>>
!Single = !idr.graded<many, counted, !idr.data<#Lazy @single>>
!Running = !idr.graded<many, counted, !idr.data<#Lazy @running>>
!Forced = !idr.graded<many, counted, !idr.data<#Lazy @forced>>
!Lazy = !idr.graded<many, counted, !idr.data<#Lazy>>
!Str = !idr.graded<many, static, !idr.str>
idr.program @forcedThrough root(@main) stage(first) {
  idr.func @single(%n: i64) -> i64 {
    idr.return %n : i64
  }
  idr.func @main() {
    %byte = idr.io.get_byte : () -> i32
    %n = arith.extui %byte : i32 to i64
    %cell = idr.data.con(%n : i64) : !Single1
    %many = idr.lin.cast %cell : !Single1 -> !Single
    %v = idr.memo.run %many : !Single -> i64 {
    ^bb0(%c: i64):
      idr.memo.yield %c : i64 then %c : i64
    }
    %lazy = idr.data.reindex %many : !Single to !Lazy
    %r = idr.data.match %lazy : !Lazy -> (f64) {
    case @single(%p: !Single) {
      %one = arith.constant 1.0 : f64
      idr.yield %one : f64
    }
    case @running(%q: !Running) {
      idr.crash.cause suspension_forced_itself at #idr.site<"Main.idr", 1, 1, "Main.force">
    }
    case @forced(%f: !Forced) {
      %x = idr.data.field %f[0] : !Forced -> i64
      %real = arith.sitofp %x : i64 to f64
      idr.yield %real : f64
    }
    }
    %e = math.exp %r : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}
