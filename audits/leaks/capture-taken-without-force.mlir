// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// @peek matches a memo cell in its label state and drops the capture the
// case binds owned, with no force: the cell keeps the capture and frees it
// again when it dies. Today: accepted. Proposed: refused, a label's fields
// are views of the cell.
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
  idr.func @peek(%t: !idr.q<many, borrow, !idr.box<!T>>) -> i64 {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!T>> -> (i64) {
    case @lbl(%s: !idr.own<!idr.str>) {
      idr.drop %s : !idr.own<!idr.str>
      %c = arith.constant 1 : i64
      idr.yield %c : i64
    }
    case @running() {
      %c = arith.constant 2 : i64
      idr.yield %c : i64
    }
    case @forced(%v: !idr.q<many, borrow, !idr.str>) {
      %c = arith.constant 3 : i64
      idr.yield %c : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}
