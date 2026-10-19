// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// @stat reads the forced value of a static memo cell, a counted value that
// static data holds, and settles it into another memo cell without a
// reference of its own: two holders, one reference, a double release. Today:
// accepted: isStatic makes every value read from static data untracked.
// Proposed: refused, a static value is a view, and a view moves nowhere
// without an idr.dup.
// See audits/leaks.md.
!T = !idr.data<"T", memo [@lbl(!idr.str) label @lbl, @running() running, @forced(!idr.str) forced]>
idr.program @"fx" root(@Main.main) stage(owned) {
  idr.func @lbl(%s: !idr.q<many, borrow, !idr.str>) -> !idr.own<!idr.str> attributes {total} {
    %r = idr.dup %s : !idr.q<many, borrow, !idr.str>
    return %r : !idr.own<!idr.str>
  }
  idr.func @T.force(%t: !idr.q<many, borrow, !idr.box<!T>>) -> !idr.own<!idr.str> {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!T>> -> (!idr.own<!idr.str>) {
    case @lbl(%s: !idr.own<!idr.str>) {
      idr.memo.enter %t : !idr.q<many, borrow, !idr.box<!T>>
      %b = idr.borrow %s : !idr.own<!idr.str>
      %v = idr.call @lbl(%b) : (!idr.q<many, borrow, !idr.str>) -> !idr.own<!idr.str>
      idr.drop %s : !idr.own<!idr.str>
      %vb = idr.borrow %v : !idr.own<!idr.str>
      %v2 = idr.dup %vb : !idr.q<many, borrow, !idr.str>
      idr.memo.settle %t, %v2 : !idr.q<many, borrow, !idr.box<!T>>, !idr.own<!idr.str>
      idr.yield %v : !idr.own<!idr.str>
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.q<many, borrow, !idr.str>) {
      %d = idr.dup %v : !idr.q<many, borrow, !idr.str>
      idr.yield %d : !idr.own<!idr.str>
    }
    }
    return %r : !idr.own<!idr.str>
  }
  idr.func @stat(%o: !idr.q<many, borrow, !idr.box<!T>>) -> !idr.own<!idr.str> {
    %t = idr.constant !idr.q<many, borrow, !idr.box<!T>> #idr.con<!T, @lbl, ["abc"]>
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!T>> -> (!idr.own<!idr.str>) {
    case @lbl(%s: !idr.own<!idr.str>) {
      idr.memo.enter %t : !idr.q<many, borrow, !idr.box<!T>>
      %b = idr.borrow %s : !idr.own<!idr.str>
      %v = idr.call @lbl(%b) : (!idr.q<many, borrow, !idr.str>) -> !idr.own<!idr.str>
      idr.drop %s : !idr.own<!idr.str>
      %vb = idr.borrow %v : !idr.own<!idr.str>
      %v2 = idr.dup %vb : !idr.q<many, borrow, !idr.str>
      idr.memo.settle %t, %v2 : !idr.q<many, borrow, !idr.box<!T>>, !idr.own<!idr.str>
      idr.yield %v : !idr.own<!idr.str>
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.q<many, borrow, !idr.str>) {
      idr.memo.settle %o, %v : !idr.q<many, borrow, !idr.box<!T>>, !idr.q<many, borrow, !idr.str>
      %d = idr.dup %v : !idr.q<many, borrow, !idr.str>
      idr.yield %d : !idr.own<!idr.str>
    }
    }
    return %r : !idr.own<!idr.str>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}
