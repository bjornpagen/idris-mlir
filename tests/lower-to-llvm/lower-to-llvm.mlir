// RUN: idris-mlir-opt %s --idr-target --idr-lower --idr-entry --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-llvm,lowered,direct-calls,calls=@Thunk.force:@add,calls=@Prog.main:@Thunk.force -o /dev/null
// After idr-lower, upstream's conversions take the program to the LLVM
// dialect alone, and no cast is left. No cell holds code: a force is a
// call of its memo sum's dispatch, which calls the label's function by
// name, for a static cell and a new one alike, so no call goes through a
// value. LLVM takes the module as it is: given the build's target, its
// program forces the static cell twice, the second time reading the value
// the first moved into it, and the new cell once, and exits with 42 + 4 + 42,
// as the program as written and the reference at the end (REF) do
// (%differential, on the one input, none, since it reads none).
// STDIN:
!Thunk = !idr.data<"Thunk", memo [@add(i64, i64) label @add, @running() running, @forced(i64) forced]>
idr.program @"to-llvm" root(@Prog.main) stage(owned) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @Thunk.force(%t: !idr.q<many, borrow, !idr.box<!Thunk>>) -> i64 {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!Thunk>> -> (i64) {
    case @add(%k: i64, %x: i64) {
      %v = idr.memo.run %t : !idr.q<many, borrow, !idr.box<!Thunk>> @add -> i64 {
      ^bb0(%kc: i64, %xc: i64):
        %v0 = idr.call @add(%kc, %xc) : (i64, i64) -> i64
        idr.array.yield %v0, %v0 : i64, i64
      }
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
    %c = idr.constant !idr.q<many, borrow, !idr.box<!Thunk>> #idr.con<!Thunk, @add, [40, 2]>
    %two = arith.constant 2 : i64
    %k = idr.cell.new : !idr.cell<!idr.box<!Thunk>, @add>
    %d = idr.cell.init %k : !idr.cell<!idr.box<!Thunk>, @add> (%two : i64, %two : i64)
    %e = idr.borrow %d : !idr.own<!idr.box<!Thunk>>
    %r = idr.call @Thunk.force(%c) : (!idr.q<many, borrow, !idr.box<!Thunk>>) -> i64
    %s = idr.call @Thunk.force(%e) : (!idr.q<many, borrow, !idr.box<!Thunk>>) -> i64
    %again = idr.call @Thunk.force(%c) : (!idr.q<many, borrow, !idr.box<!Thunk>>) -> i64
    idr.drop %d : !idr.own<!idr.box<!Thunk>>
    %t = arith.addi %r, %s : i64
    %u = arith.addi %t, %again : i64
    return %u : i64
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) {
// REF:   idr.func @Prog.main() -> i64 {
// REF:     %c = arith.constant 88 : i64
// REF:     return %c : i64
// REF:   }
// REF: }
