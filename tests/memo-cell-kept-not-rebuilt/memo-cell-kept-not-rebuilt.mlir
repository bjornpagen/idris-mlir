// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main,folded=@use})' -verify-diagnostics -o /dev/null
// A memo cell is one cell however many values name it: a force through one
// is seen through every other, so its function runs once. A copy keyed by
// the shape of a call's argument builds each constructor of the key again,
// so it may build a memo cell again only where the call takes the
// caller's cell whole; a cell the caller keeps is passed to the copy as it
// is. In each program @main builds a memo cell of a byte read at run time
// and passes it, at its constructor's type, to @use, which takes that type
// and a count read at run time: at zero @use widens the cell to its family
// and matches on it, the pending case forcing the cell and yielding 2.0;
// otherwise it passes the cell to itself in a call that is no tail call, so
// @use is a function on a cycle wherever it is called. In the first @main
// matches on the cell again after the call, so it keeps the cell: no copy
// of @use builds a cell of its own, and the match in @use is left to run
// whichever case the cell is in, the exp of what it yields no constant.
// Were the cell built again in a copy, the copy's match would run the
// pending case of a cell nothing had forced, its function running there
// and again in @main's match, and the exp of its 2.0 would be computed
// from a constant alone. In the second the call takes the cell whole, so
// the copy keyed by it builds the one cell, whose match runs the pending
// case: the exp of its 2.0 is computed from a constant alone, wherever the
// copy's body stands after inlining. After the first stage nothing else in
// @use, its copies or @main computes from constants alone.
#Lazy = #idr.family<"Lazy" memo [] {
    @single fn @single (i64)
  } forced (i64)>
!Single1 = !idr.graded<once, counted, !idr.data<#Lazy @single>>
!Single = !idr.graded<many, counted, !idr.data<#Lazy @single>>
!Running = !idr.graded<many, counted, !idr.data<#Lazy @running>>
!Forced = !idr.graded<many, counted, !idr.data<#Lazy @forced>>
!Lazy = !idr.graded<many, counted, !idr.data<#Lazy>>
!Str = !idr.graded<many, static, !idr.str>
idr.program @kept root(@main) stage(first) {
  idr.func @single(%n: i64) -> i64 {
    idr.return %n : i64
  }
  idr.func @use(%cell: !Single, %k: i64) -> f64 {
    %r = idr.lit.match %k : i64 -> (f64) {
      case 0(%zero: i64) {
        %lazy = idr.data.reindex %cell : !Single to !Lazy
        %v = idr.data.match %lazy : !Lazy -> (f64) {
        case @single(%p: !Single) {
          %x = idr.memo.run %p : !Single -> i64 {
          ^bb0(%c: i64):
            %h = idr.call @single(%c) : (i64) -> i64
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
        %e = math.exp %v : f64
        idr.yield %e : f64
      } default(%d: i64) {
        %one = arith.constant 1 : i64
        %j = arith.subi %d, %one : i64
        %t = idr.call @use(%cell, %j) : (!Single, i64) -> f64
        %onef = arith.constant 1.0 : f64
        %s = arith.addf %t, %onef : f64
        idr.yield %s : f64
      }
    }
    idr.return %r : f64
  }
  idr.func @main() {
    %byte = idr.io.get_byte : () -> i32
    %n = arith.extui %byte : i32 to i64
    %count = idr.io.get_byte : () -> i32
    %k = arith.extui %count : i32 to i64
    %cell = idr.data.con(%n : i64) : !Single1
    %many = idr.lin.cast %cell : !Single1 -> !Single
    %lazy = idr.data.reindex %many : !Single to !Lazy
    %used = idr.call @use(%many, %k) : (!Single, i64) -> f64
    %r = idr.data.match %lazy : !Lazy -> (f64) {
    case @single(%p: !Single) {
      %x = idr.memo.run %p : !Single -> i64 {
      ^bb0(%c: i64):
        %h = idr.call @single(%c) : (i64) -> i64
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
    %e = math.exp %r : f64
    %sum = arith.addf %used, %e : f64
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
idr.program @moved root(@main) stage(first) {
  idr.func @single(%n: i64) -> i64 {
    idr.return %n : i64
  }
  idr.func @use(%cell: !Single, %k: i64) -> f64 {
    %r = idr.lit.match %k : i64 -> (f64) {
      case 0(%zero: i64) {
        %lazy = idr.data.reindex %cell : !Single to !Lazy
        %v = idr.data.match %lazy : !Lazy -> (f64) {
        case @single(%p: !Single) {
          %x = idr.memo.run %p : !Single -> i64 {
          ^bb0(%c: i64):
            %h = idr.call @single(%c) : (i64) -> i64
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
        %e = math.exp %v : f64
        idr.yield %e : f64
      } default(%d: i64) {
        %one = arith.constant 1 : i64
        %j = arith.subi %d, %one : i64
        %t = idr.call @use(%cell, %j) : (!Single, i64) -> f64
        %onef = arith.constant 1.0 : f64
        %s = arith.addf %t, %onef : f64
        idr.yield %s : f64
      }
    }
    idr.return %r : f64
  }
  idr.func @main() {
    %byte = idr.io.get_byte : () -> i32
    %n = arith.extui %byte : i32 to i64
    %count = idr.io.get_byte : () -> i32
    %k = arith.extui %count : i32 to i64
    %cell = idr.data.con(%n : i64) : !Single1
    %many = idr.lin.cast %cell : !Single1 -> !Single
    %used = idr.call @use(%many, %k) : (!Single, i64) -> f64
    %text = idr.str.show_double %used : (f64) -> !Str
    idr.io.put_str %text : (!Str) -> ()
    idr.return
  }
}
