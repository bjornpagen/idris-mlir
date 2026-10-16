// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=lowered,direct-calls,calls=@__idr_release_cafs:@idris_rt_caf_release,calls=@Prog.main:@Tail.force -o /dev/null
// NEEDS-ACCEPTANCE: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
// NEEDS-ACCEPTANCE: the syntax of idr.memo.enter and idr.memo.settle and the dispatch idr-defunctionalize makes.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// A lazy constant is a memo cell in static data, which its first force
// writes, once: its force is a call of the memo sum's dispatch, which
// enters and settles the cell where it is. So its global is not constant,
// and its info word says the thunk kind (1 << 24) with its label's tag,
// here 0. Every other static cell stays constant, among them a constant
// stream whose tail is that cell: it holds the cell's address.
// @__idr_release_cafs releases what each such cell holds once forced,
// when the program ends. The globals are the runtime's static data.
!Tail = !idr.data<"Tail", memo [@ones() label @ones, @running() running, @forced(!idr.box<!idr.data<"Stream", plain [@Cons(i64, !idr.box<!idr.data<"Tail">>)]>>) forced]>
!Stream = !idr.data<"Stream", plain [@Cons(i64, !idr.box<!idr.data<"Tail", memo [@ones() label @ones, @running() running, @forced(!idr.box<!idr.data<"Stream">>) forced]>>)]>
idr.program @"static-thunk" root(@Prog.main) stage(first) {
  // ones = 1 :: ones: its tail is the thunk of the definition itself.
  idr.func @ones() -> !idr.box<!Stream> attributes {total} {
    %s = idr.constant #idr.con<!Stream, @Cons, [1, #idr.con<!Tail, @ones, []>]> : !idr.box<!Stream>
    return %s : !idr.box<!Stream>
  }
  idr.func @Tail.force(%t: !idr.box<!Tail>) -> !idr.box<!Stream> {
    %r = idr.match %t : !idr.box<!Tail> -> (!idr.box<!Stream>) {
    case @ones() {
      idr.memo.enter %t : !idr.box<!Tail>
      %v = idr.call @ones() : () -> !idr.box<!Stream>
      idr.memo.settle %t, %v : !idr.box<!Tail>, !idr.box<!Stream>
      idr.yield %v : !idr.box<!Stream>
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.box<!Stream>) {
      idr.yield %v : !idr.box<!Stream>
    }
    }
    return %r : !idr.box<!Stream>
  }
  idr.func @Prog.main() -> i64 {
    %s = idr.call @ones() : () -> !idr.box<!Stream>
    %t = idr.field %s : !idr.box<!Stream> @Cons[1] -> !idr.box<!Tail>
    %u = idr.call @Tail.force(%t) : (!idr.box<!Tail>) -> !idr.box<!Stream>
    %h = idr.field %u : !idr.box<!Stream> @Cons[0] -> i64
    return %h : i64
  }
}
