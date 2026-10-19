// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A cell of the frame (idr.cell.stack) is settled into a memo cell the
// caller holds: the memo cell outlives the frame, so it points into a dead
// frame after the return (the leak of static-lazy-list.idr and the crash of
// shared-lazy-list.idr). Today: accepted. Proposed: refused, a value of
// lifetime frame never moves into a place that exists before the op.
// See audits/leaks.md.
!P = !idr.data<"P", plain [@MkP(!idr.str)]>
!U = !idr.data<"U", memo [@mk(!idr.str) label @mk, @running() running, @forced(!idr.box<!P>) forced]>
idr.program @"fx" root(@Main.main) stage(owned) {
  idr.func @mk(%s: !idr.q<many, borrow, !idr.str>) -> !idr.own<!idr.box<!P>> attributes {total} {
    %d = idr.dup %s : !idr.q<many, borrow, !idr.str>
    %c = idr.cell.new : !idr.cell<!idr.box<!P>, @MkP>
    %b = idr.cell.init %c : !idr.cell<!idr.box<!P>, @MkP> (%d : !idr.own<!idr.str>)
    return %b : !idr.own<!idr.box<!P>>
  }
  idr.func @U.force(%t: !idr.q<many, borrow, !idr.box<!U>>) -> !idr.own<!idr.box<!P>> {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!U>> -> (!idr.own<!idr.box<!P>>) {
    case @mk(%s: !idr.own<!idr.str>) {
      idr.memo.enter %t : !idr.q<many, borrow, !idr.box<!U>>
      %c = idr.cell.stack : !idr.cell<!idr.box<!P>, @MkP>
      %v = idr.cell.init %c : !idr.cell<!idr.box<!P>, @MkP> (%s : !idr.own<!idr.str>)
      %vb = idr.borrow %v : !idr.own<!idr.box<!P>>
      %v2 = idr.dup %vb : !idr.q<many, borrow, !idr.box<!P>>
      idr.memo.settle %t, %v2 : !idr.q<many, borrow, !idr.box<!U>>, !idr.own<!idr.box<!P>>
      idr.yield %v : !idr.own<!idr.box<!P>>
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.q<many, borrow, !idr.box<!P>>) {
      %d = idr.dup %v : !idr.q<many, borrow, !idr.box<!P>>
      idr.yield %d : !idr.own<!idr.box<!P>>
    }
    }
    return %r : !idr.own<!idr.box<!P>>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}
