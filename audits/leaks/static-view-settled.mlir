// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// @stat reads the forced value of a static memo cell, a value static data
// holds, and moves it into another memo cell's forced state without a
// reference of its own: two holders, one reference. Persistence makes the
// value static at run time (idris_rt_persist_held), so the run counts
// nothing; but the owned walk accepts it only because isStatic's search of
// the definition chain calls the view untracked. Proposed (leaks.md §3.1,
// open): static is a view's lifetime in the grade, and a view moves
// nowhere without an idr.dup, so this is refused.
!T = !idr.data<"T", memo [@lbl(!idr.str) label @lbl, @running() running, @forced(!idr.str) forced]>
idr.program @"fx" root(@Main.main) stage(owned) {
  idr.func @lbl(%s: !idr.q<many, borrow, !idr.str>) -> !idr.own<!idr.str> attributes {total} {
    %r = idr.dup %s : !idr.q<many, borrow, !idr.str>
    return %r : !idr.own<!idr.str>
  }
  idr.func @stat(%o: !idr.q<many, borrow, !idr.box<!T>>) -> i64 {
    %t = idr.constant !idr.q<many, borrow, !idr.box<!T>> #idr.con<!T, @forced, ["abc"]>
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!T>> -> (i64) {
    case @lbl(%s: !idr.q<many, borrow, !idr.str>) {
      %c = arith.constant 0 : i64
      idr.yield %c : i64
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.q<many, borrow, !idr.str>) {
      idr.memo.run %o : !idr.q<many, borrow, !idr.box<!T>> @lbl {
      ^bb0(%c: !idr.own<!idr.str>):
        idr.drop %c : !idr.own<!idr.str>
        idr.array.yield %v : !idr.q<many, borrow, !idr.str>
      }
      %c = arith.constant 1 : i64
      idr.yield %c : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}
