// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A cell of the frame returned. Today: accepted. Proposed: refused, a
// value of lifetime frame is never returned.
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
  idr.func @ret(%s: !idr.own<!idr.str>) -> !idr.own<!idr.box<!T>> {
    %c = idr.cell.stack : !idr.cell<!idr.box<!T>, @lbl>
    %b = idr.cell.init %c : !idr.cell<!idr.box<!T>, @lbl> (%s : !idr.own<!idr.str>)
    return %b : !idr.own<!idr.box<!T>>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}
