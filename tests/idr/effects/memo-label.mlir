// RUN: idris-mlir-opt %s --idr-effects --idr-expect=holds=effects=@divides:crash,effects=@makes:none,effects=@done:none,effects=@Lazy.force:crash,effects=@forces:crash -o /dev/null
// NEEDS-ACCEPTANCE: the dispatch idr-defunctionalize makes of a memo sum (R06) and the syntax of idr.memo.enter and idr.memo.settle (R02).
// A memo sum stands to a suspension as a sum of closures stands to a
// closure, and a force is a call of the sum's dispatch, `<sum>.force`,
// which calls the function of each label it may find in the cell. So what
// a label may do flows to the forcer through that call, as any callee's
// does: the dispatch may crash when a label may, and when the cell is
// found running, a suspension that forces itself. Making a cell, of a label
// or of a state, runs nothing: the maker does no more than its own body
// does.

!Lazy = !idr.data<"Lazy", memo [@divides(i64) label @divides, @running() running, @forced(i64) forced]>
idr.program @"memo-label" root(@main) stage(first) {
  idr.func @divides(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    %r = idr.div signed %x, %y : i64
    return %r : i64
  }
  idr.func @makes(%x: i64) -> !idr.box<!Lazy> attributes {total} {
    %t = idr.con !idr.box<!Lazy> @divides(%x : i64)
    return %t : !idr.box<!Lazy>
  }
  idr.func @done(%x: i64) -> !idr.box<!Lazy> attributes {total} {
    %t = idr.con !idr.box<!Lazy> @forced(%x : i64)
    return %t : !idr.box<!Lazy>
  }
  idr.func @Lazy.force(%t: !idr.box<!Lazy>) -> i64 attributes {total} {
    %r = idr.match %t : !idr.box<!Lazy> -> (i64) {
    case @divides(%x: i64) {
      idr.memo.enter %t : !idr.box<!Lazy>
      %v = idr.call @divides(%x) : (i64) -> i64
      idr.memo.settle %t, %v : !idr.box<!Lazy>, i64
      idr.yield %v : i64
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: i64) {
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
  idr.func @forces(%x: i64) -> i64 attributes {total} {
    %t = idr.call @makes(%x) : (i64) -> !idr.box<!Lazy>
    %v = idr.call @Lazy.force(%t) : (!idr.box<!Lazy>) -> i64
    return %v : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 7 : i64
    %v = idr.call @forces(%c) : (i64) -> i64
    return %v : i64
  }
}
