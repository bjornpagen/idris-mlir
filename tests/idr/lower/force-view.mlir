// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,direct-calls,crash-sites=@Thunk.force:1,calls=@Thunk.force:@one,calls=@Thunk.force:@plus,calls-only=@Thunk.force:[@one,@plus,@idris_rt_crash],aligned-access' -o /dev/null
// RUN: FileCheck %s < %t.mlir
// NEEDS-ACCEPTANCE: the syntax of idr.memo.enter and idr.memo.settle and the dispatch idr-defunctionalize makes of a memo sum, and the header words the lowering writes for them.
// A force is a call of its memo sum's dispatch, `<sum>.force`, which
// idr-defunctionalize makes: a match on the cell's state. A cell in a
// label's state has its captures moved out to the dispatch, is marked
// running (idr.memo.enter) before the label's function is called, so a
// force of it from inside the call finds it running and crashes, as a
// suspension that forces itself does; the value is then stored in the cell,
// which is marked forced (idr.memo.settle), and shared with the forcer. A
// forced cell's value is read with no call at all. So the dispatch calls
// each label's function directly, by name, and asks the runtime for
// nothing but the crash of a cell forced from inside its own force.
// Entering and settling write the cell's header: the memo sum is a box of
// @one and @plus, then running and forced, so running is tag 2 and forced
// tag 3, each with the thunk kind, 1 << 24, the runtime's header words.
// CHECK-LABEL: func.func private @Thunk.force(
// CHECK-DAG: llvm.mlir.constant(16777218 : i32)
// CHECK-DAG: llvm.mlir.constant(16777219 : i32)
!Thunk = !idr.data<"Thunk", memo [@one() label @one, @plus(i64) label @plus, @running() running, @forced(i64) forced]>
idr.program @"force-view" root(@Main.main) stage(owned) {
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @plus(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func @Thunk.force(%t: !idr.q<many, borrow, !idr.box<!Thunk>>) -> i64 {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!Thunk>> -> (i64) {
    case @one() {
      idr.memo.enter %t : !idr.q<many, borrow, !idr.box<!Thunk>>
      %v = idr.call @one() : () -> i64
      idr.memo.settle %t, %v : !idr.q<many, borrow, !idr.box<!Thunk>>, i64
      idr.yield %v : i64
    }
    case @plus(%x: i64) {
      idr.memo.enter %t : !idr.q<many, borrow, !idr.box<!Thunk>>
      %v = idr.call @plus(%x) : (i64) -> i64
      idr.memo.settle %t, %v : !idr.q<many, borrow, !idr.box<!Thunk>>, i64
      idr.yield %v : i64
    }
    case @running() {
      idr.crash "a suspension forced itself" loc("Main.idr":9:3)
      ub.unreachable
    }
    case @forced(%v: i64) {
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %two = arith.constant 2 : i64
    %t = idr.con !idr.own<!idr.box<!Thunk>> @plus(%two : i64)
    %b = idr.borrow %t : !idr.own<!idr.box<!Thunk>>
    %v = idr.call @Thunk.force(%b) : (!idr.q<many, borrow, !idr.box<!Thunk>>) -> i64
    idr.drop %t : !idr.own<!idr.box<!Thunk>>
    return %v : i64
  }
}
