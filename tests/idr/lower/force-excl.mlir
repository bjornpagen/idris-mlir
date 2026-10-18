// NEEDS-ACCEPTANCE: the memo cell is an idr.cell.new and its idr.cell.init, its box written exclusive (S3); the lowered calls are as before.
// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,direct-calls,writes-nothing=@once,calls=@once:@one,calls=@once:@plus,calls-only=@once:[@one,@plus,@idris_rt_free_cell,@idris_rt_crash],crash-sites=@once:1' -o /dev/null
// NEEDS-ACCEPTANCE: the form a force of an exclusive memo cell takes after idr-rc: its state taken apart and its token freed, with no idr.memo.enter or idr.memo.settle; and the syntax of idr.take of a constructor without fields.
// NEEDS-ACCEPTANCE: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves.
// A memo cell nothing else holds is forced once, so nothing is memoized:
// its captures, or its value, move out of it, its memory goes, and the
// cell is never written. A cell in a label's state calls the label's
// function directly with its captures, after its memory is freed.
!Thunk = !idr.data<"Thunk", memo [@one() label @one, @plus(i64) label @plus, @running() running, @forced(i64) forced]>
idr.program @"force-excl" root(@Main.main) stage(owned) {
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @plus(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func @once(%t: !idr.excl<!idr.box<!Thunk>>) -> i64 {
    %v = idr.borrow %t : !idr.excl<!idr.box<!Thunk>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!Thunk>> -> (i64) {
    case @one() {
      %k = idr.take %t : !idr.excl<!idr.box<!Thunk>> @one -> (!idr.excl<!idr.token>)
      idr.drop %k : !idr.excl<!idr.token>
      %y = idr.call @one() : () -> i64
      idr.yield %y : i64
    }
    case @plus(%x: i64) {
      %k:2 = idr.take %t : !idr.excl<!idr.box<!Thunk>> @plus -> (!idr.excl<!idr.token>, i64)
      idr.drop %k#0 : !idr.excl<!idr.token>
      %y = idr.call @plus(%k#1) : (i64) -> i64
      idr.yield %y : i64
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%f: i64) {
      %k:2 = idr.take %t : !idr.excl<!idr.box<!Thunk>> @forced -> (!idr.excl<!idr.token>, i64)
      idr.drop %k#0 : !idr.excl<!idr.token>
      idr.yield %k#1 : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %two = arith.constant 2 : i64
    %k = idr.cell.new : !idr.cell<!idr.box<!Thunk>, @plus>
    %t = idr.cell.init %k : !idr.cell<!idr.box<!Thunk>, @plus> (%two : i64) -> !idr.excl<!idr.box<!Thunk>>
    %v = idr.call @once(%t) : (!idr.excl<!idr.box<!Thunk>>) -> i64
    return %v : i64
  }
}
