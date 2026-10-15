// RUN: idris-mlir-opt %s --idr-lower --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-llvm,lowered,direct-calls,calls=@Thunk.force:@add,calls=@Prog.main:@Thunk.force -o /dev/null
// NEEDS-ACCEPTANCE: the syntax of idr.memo.enter and idr.memo.settle and the dispatch idr-defunctionalize makes.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// After idr-lower, upstream's conversions take the program to the LLVM
// dialect alone, and no cast is left. No cell holds code: a force is a
// call of its memo sum's dispatch, which calls the label's function by
// name, for a static cell and a new one alike, so no call goes through a
// value.
!Thunk = !idr.data<"Thunk", memo [@add(i64, i64) label @add, @running() running, @forced(i64) forced]>
idr.program @"to-llvm" root(@Prog.main) stage(owned) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @Thunk.force(%t: !idr.q<many, borrow, !idr.box<!Thunk>>) -> i64 {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!Thunk>> -> (i64) {
    case @add(%k: i64, %x: i64) {
      idr.memo.enter %t : !idr.q<many, borrow, !idr.box<!Thunk>>
      %v = idr.call @add(%k, %x) : (i64, i64) -> i64
      idr.memo.settle %t, %v : !idr.q<many, borrow, !idr.box<!Thunk>>, i64
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
  idr.func @Prog.main() -> i64 {
    %c = idr.constant #idr.con<!Thunk, @add, [40, 2]> : !idr.box<!Thunk>
    %two = arith.constant 2 : i64
    %d = idr.con !idr.own<!idr.box<!Thunk>> @add(%two : i64, %two : i64)
    %e = idr.borrow %d : !idr.own<!idr.box<!Thunk>>
    %r = idr.call @Thunk.force(%c) : (!idr.q<many, borrow, !idr.box<!Thunk>>) -> i64
    %s = idr.call @Thunk.force(%e) : (!idr.q<many, borrow, !idr.box<!Thunk>>) -> i64
    idr.drop %d : !idr.own<!idr.box<!Thunk>>
    %t = arith.addi %r, %s : i64
    return %t : i64
  }
}
