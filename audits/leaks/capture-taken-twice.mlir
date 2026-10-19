// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The force takes its label's capture over twice: the case binds it owned
// (caseFieldType) and an idr.field reads it owned again; both are dropped,
// so the capture is released twice. Today: accepted (idris-mlir-opt exits
// 0): an owned result is given a reference of its own whatever made it.
// Proposed: refused, the field read is a view, and an owned capture has one
// source, the memo.run that moves it out of the cell.
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
      %s2 = idr.field %t : !idr.q<many, borrow, !idr.box<!T>> @lbl[0] -> !idr.own<!idr.str>
      idr.drop %s2 : !idr.own<!idr.str>
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
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}
