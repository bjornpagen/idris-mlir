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
// length is 19. In the fourth `Just 5 : Maybe Integer`, a small big in its
// word, is a constant, and its field, read at the static hold the read
// gives rather than the hold it was given at, is 5, read off the constant:
// the read takes no field the op gave, so only the constant makes it 5.
// The fifth to seventh read a constant built by idr.data.con cell by cell:
// the characters 'h' and 'i' pack to "hi", of length 2; "ab" and "c"
// concatenate to "abc", of length 3; and the numeral of two successors of
// zero is 2, whose text's length is 1.
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

// -----

#M = #idr.family<"Maybe" [] {
    @Nothing ()
    @Just (!idr.big)
  }>
!Just = !idr.graded<many, static, !idr.data<#M @Just>>
!BigS = !idr.graded<many, static, !idr.big>
!Str = !idr.graded<many, static, !idr.str>
idr.program @word root(@main) stage(first) {
  idr.func @main() {
    %c5 = arith.constant 5 : i64
    %five = idr.big.small %c5 : (i64) -> !idr.big
    %just = idr.data.con(%five : !idr.big) : !Just
    %field = idr.data.field %just[0] : !Just -> !BigS
    %shown = idr.big.show %field : (!BigS) -> !Str
    %length = idr.str.length %shown : (!Str) -> i64
    %real = arith.sitofp %length : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %real : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}

// -----

#Chars = #idr.family<"Chars" [] {
    @Nil ()
    @Cons (i32, !idr.self)
  }>
!Nil = !idr.data<#Chars @Nil>
!Cons = !idr.data<#Chars @Cons>
!Str = !idr.graded<many, static, !idr.str>
idr.program @pack root(@main) stage(first) {
  idr.func @main() {
    %h = arith.constant 104 : i32
    %i = arith.constant 105 : i32
    %nil = idr.data.con() : !Nil
    %tail = idr.data.con(%i : i32, %nil : !Nil) : !Cons
    %list = idr.data.con(%h : i32, %tail : !Cons) : !Cons
    %packed = idr.str.pack %list : (!Cons) -> !Str
    %length = idr.str.length %packed : (!Str) -> i64
    %real = arith.sitofp %length : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %real : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}

// -----

#Strs = #idr.family<"Strs" [] {
    @Nil ()
    @Cons (!idr.str, !idr.self)
  }>
!Nil = !idr.graded<many, static, !idr.data<#Strs @Nil>>
!Cons = !idr.graded<many, static, !idr.data<#Strs @Cons>>
!Str = !idr.graded<many, static, !idr.str>
idr.program @concat root(@main) stage(first) {
  idr.func @main() {
    %ab = idr.constant !Str "ab"
    %c = idr.constant !Str "c"
    %nil = idr.data.con() : !Nil
    %tail = idr.data.con(%c : !Str, %nil : !Nil) : !Cons
    %list = idr.data.con(%ab : !Str, %tail : !Cons) : !Cons
    %joined = idr.str.concat %list : (!Cons) -> !Str
    %length = idr.str.length %joined : (!Str) -> i64
    %real = arith.sitofp %length : i64 to f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %real : f64
    %text = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}

// -----

#Count = #idr.family<"Count" [] {
    @Zero ()
    @Succ (!idr.self)
  }>
!Zero = !idr.data<#Count @Zero>
!Succ = !idr.data<#Count @Succ>
!NatS = !idr.graded<many, static, !idr.nat<_>>
!BigS = !idr.graded<many, static, !idr.big>
!Str = !idr.graded<many, static, !idr.str>
idr.program @numeral root(@main) stage(first) {
  idr.func @main() {
    %zero = idr.data.con() : !Zero
    %one = idr.data.con(%zero : !Zero) : !Succ
    %two = idr.data.con(%one : !Succ) : !Succ
    %n = idr.numeral.to_nat %two : !Succ -> !NatS
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
