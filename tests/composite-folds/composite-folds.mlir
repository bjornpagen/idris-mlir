// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main})' -verify-diagnostics -o /dev/null
// The folds of constants made of constants, each one condition over where
// a constant lives: after the first stage nothing in @main computes from
// constants alone but exp, which no fold computes, and whose operand each
// program makes a constant only if its fold ran. In the first program a
// pair of 3 and 4, a value of words used any number of times, is a
// constant, and its second field read off it is 4: so the sum of 0 and the
// field, as a Double, is 4.0. In the second the operating system the module's target
// names is the string "darwin", whose length is 6. In the third a natural
// past the small range is the same big under the big's type, whose text's
// length is 19.
#P = #idr.family<"P" [] {
    @MkP (i64, i64)
  }>
!MkP = !idr.data<#P @MkP>
!Str = !idr.graded<many, static, !idr.str>
idr.program @built root(@main) stage(first) {
  idr.func @main() {
    %zero = arith.constant 0 : i64
    %three = arith.constant 3 : i64
    %four = arith.constant 4 : i64
    %p = idr.data.con(%three : i64, %four : i64) : !MkP
    %second = idr.data.field %p[1] : !MkP -> i64
    %sum = arith.addi %zero, %second : i64
    %real = arith.sitofp %sum : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %real : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}

// -----

!Str = !idr.graded<many, static, !idr.str>
module attributes {llvm.target = #llvm.target<triple = "aarch64-apple-darwin", chip = "">} {
  idr.program @platform root(@main) stage(first) {
    idr.func @main() {
      %os = idr.platform.os : () -> !Str
      %n = idr.str.length %os : (!Str) -> i64
      %real = arith.sitofp %n : i64 to f64
      // expected-error @below {{expected folded: }}
      %e = math.exp %real : f64
      %text = idr.str.show_double %e : (f64) -> !Str
      idr.io.put_str %text : (!Str) -> ()
      idr.return
    }
  }
}

// -----

!Str = !idr.graded<many, static, !idr.str>
!NatS = !idr.graded<many, static, !idr.nat<_>>
!BigS = !idr.graded<many, static, !idr.big>
idr.program @natural root(@main) stage(first) {
  idr.func @main() {
    %n = idr.constant !NatS #idr.big<4611686018427387904>
    %b = idr.nat.to_big %n : (!NatS) -> !BigS
    %shown = idr.big.show %b : (!BigS) -> !Str
    %length = idr.str.length %shown : (!Str) -> i64
    %real = arith.sitofp %length : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %real : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}
