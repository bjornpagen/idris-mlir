// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main})' -verify-diagnostics -o /dev/null
// A memo cell says the constructor that built it only until something may
// force it, and a force reaches the cell under whatever value holds it: a
// match's refined binding of the widened cell, a call the cell is passed
// to. So a match on the cell runs the case of the constructor that built
// it only where nothing run since the cell was built may have forced it.
// In each program @main builds a memo cell of a byte read at run time,
// casts it out of its linear position and widens it to its family, then
// matches on it after a force. In the first a match on the cell runs the
// pending case, which forces the cell through the case's refined binding
// and yields 2.0, and a second match on the cell follows: nothing ran
// before the first, so it runs the pending case and the exp of its 2.0 is
// computed from a constant alone; the force ran before the second, so it
// is left to run whichever case the cell is in, and the exp of its 1.0 or
// forced value is no constant. In the second the cell is passed to the
// suspension's dispatch as defunctionalization builds it, whose call may
// force it, before the match, which is left in the same way; there the
// label's function counts down and back up, a call of itself, so the
// dispatch calls a function that is no leaf, and the call stands in @main
// when @main is first simplified. After the first stage nothing in @main
// computes from constants alone but the exp of what a match decided to run
// its pending case yields, which no fold computes.
#Lazy = #idr.family<"Lazy" memo [] {
    @single fn @single (i64)
  } forced (i64)>
!Single1 = !idr.graded<once, counted, !idr.data<#Lazy @single>>
!Single = !idr.graded<many, counted, !idr.data<#Lazy @single>>
!Running = !idr.graded<many, counted, !idr.data<#Lazy @running>>
!Forced = !idr.graded<many, counted, !idr.data<#Lazy @forced>>
!Lazy = !idr.graded<many, counted, !idr.data<#Lazy>>
!Str = !idr.graded<many, static, !idr.str>
idr.program @byMatch root(@main) stage(first) {
  idr.func @single(%n: i64) -> i64 {
    idr.return %n : i64
  }
  idr.func @main() {
    %byte = idr.io.get_byte : () -> i32
    %n = arith.extui %byte : i32 to i64
    %cell = idr.data.con(%n : i64) : !Single1
    %many = idr.lin.cast %cell : !Single1 -> !Single
    %lazy = idr.data.reindex %many : !Single to !Lazy
    %first = idr.data.match %lazy : !Lazy -> (f64) {
    case @single(%p: !Single) {
      %v = idr.memo.run %p : !Single -> i64 {
      ^bb0(%c: i64):
        %h = idr.call @single(%c) <{tail_kind = nontail}> : (i64) -> i64
        idr.memo.yield %h : i64 then %h : i64
      }
      %two = arith.constant 2.0 : f64
      idr.yield %two : f64
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
    // expected-error @below {{expected folded: }}
    %d = math.exp %first : f64
    %second = idr.data.match %lazy : !Lazy -> (f64) {
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
    %e = math.exp %second : f64
    %sum = arith.addf %d, %e : f64
    %text = idr.str.show_double %sum : (f64) -> !Str
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
!Running = !idr.graded<many, counted, !idr.data<#Lazy @running>>
!Forced = !idr.graded<many, counted, !idr.data<#Lazy @forced>>
!Lazy = !idr.graded<many, counted, !idr.data<#Lazy>>
!Str = !idr.graded<many, static, !idr.str>
idr.program @byCall root(@main) stage(first) {
  idr.func @single(%n: i64) -> i64 {
    %r = idr.lit.match %n : i64 -> (i64) {
      case 0(%zero: i64) {
        idr.yield %n : i64
      } default(%d: i64) {
        %one = arith.constant 1 : i64
        %next = arith.subi %d, %one : i64
        %t = idr.call @single(%next) <{tail_kind = nontail}> : (i64) -> i64
        %s = arith.addi %t, %one : i64
        idr.yield %s : i64
      }
    }
    idr.return %r : i64
  }
  idr.func @force(%cell: !Lazy) -> i64 {
    %v = idr.data.match %cell : !Lazy -> (i64) {
    case @single(%p: !Single) {
      %x = idr.memo.run %p : !Single -> i64 {
      ^bb0(%c: i64):
        %h = idr.call @single(%c) <{tail_kind = nontail}> : (i64) -> i64
        idr.memo.yield %h : i64 then %h : i64
      }
      idr.yield %x : i64
    }
    case @running(%q: !Running) {
      idr.crash.cause suspension_forced_itself at #idr.site<"Main.idr", 1, 1, "Main.force">
    }
    case @forced(%f: !Forced) {
      %x = idr.data.field %f[0] : !Forced -> i64
      idr.yield %x : i64
    }
    }
    idr.return %v : i64
  }
  idr.func @main() {
    %byte = idr.io.get_byte : () -> i32
    %n = arith.extui %byte : i32 to i64
    %cell = idr.data.con(%n : i64) : !Single1
    %many = idr.lin.cast %cell : !Single1 -> !Single
    %lazy = idr.data.reindex %many : !Single to !Lazy
    %forced = idr.call @force(%lazy) <{tail_kind = nontail}> : (!Lazy) -> i64
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
