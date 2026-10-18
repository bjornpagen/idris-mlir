// RUN: idris-mlir-opt %s --idr-optimize --idr-expect=holds=moves-out=@update,moves-out=@updateAt -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --canonicalize --idr-expect=holds=moves-out=@update -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --canonicalize --idr-expect=holds=moves-out=@update -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-optimize --idr-expect=holds=moves-out=@printed -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-optimize --idr-expect=holds=moves-out=@callsIO -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-optimize --idr-expect=holds=moves-out=@inMatch -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-optimize --idr-expect=holds=moves-out=@word -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// NEEDS-ACCEPTANCE: that the element moves out across the call of the pure @bump under idr-optimize and under upstream's canonicalize after idr-effects, which writes the call its callee's effects, and not across a call no pass has given effects; and that under idr-optimize it stays read across output, a call that performs IO, a write in another block, and in a word.
// A read of an element whose world goes next to a write of the same element
// moves the element out: a value read to be rebuilt and written back holds
// the one reference to its cell. An IORef's modify is one, and so is an
// array's read and write at one index, each access with its own guard of
// the index. Only computing may come between, which a call of a pure
// function does: what a call does is its own effects, which idr-effects
// writes from its callee's. A call no pass has given effects may do
// anything, so the element stays (the third RUN line). Anything that may
// read what the array holds keeps the read as it is: output on a world of
// its own, a call that performs IO, and a write in another block. A word
// holds no reference to give up. The effects are a defunctionalized
// program's, where every call names its callee, so no force or apply is
// left to say less. No function here is inlined, so @bump's call stays
// between the read and the write, and each function stays to be checked.
!R = !idr.data<"R", plain [@MkR(i64, i64)]>
idr.program @"array-moves" root(@root) stage(first) {
  idr.func @bump(%r: !idr.box<!R>) -> !idr.box<!R> attributes {total, no_inline} {
    %a = idr.field %r : !idr.box<!R> @MkR[0] -> i64
    %b = idr.field %r : !idr.box<!R> @MkR[1] -> i64
    %one = arith.constant 1 : i64
    %a1 = arith.addi %a, %one : i64
    %n = idr.con !idr.box<!R> @MkR(%a1 : i64, %b : i64)
    return %n : !idr.box<!R>
  }

  idr.func @sneaky(%s: !idr.str) -> i64 attributes {total} {
    %v = idr.world.new
    %v1 = idr.io.put_str %s, %v
    %z = arith.constant 0 : i64
    return %z : i64
  }

  idr.func @update(%ref: memref<!idr.box<!R>, #idr.world>, %w: !idr.world) -> !idr.world attributes {no_inline} {
    %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<!R>, #idr.world> -> !idr.box<!R>
    %n = idr.call @bump(%r) : (!idr.box<!R>) -> !idr.box<!R>
    %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<!R>, #idr.world>, !idr.box<!R>
    return %w2 : !idr.world
  }

  idr.func @updateAt(%a: memref<?x!idr.box<!R>, #idr.world>, %i: i64, %w: !idr.world) -> !idr.world attributes {no_inline} {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?x!idr.box<!R>, #idr.world>
    %len = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %a, "array index out of bounds" : memref<?x!idr.box<!R>, #idr.world>
    %r, %w1 = idr.array.get %a[%j], %w : memref<?x!idr.box<!R>, #idr.world> -> !idr.box<!R>
    %n = idr.call @bump(%r) : (!idr.box<!R>) -> !idr.box<!R>
    %k = idr.check.in_bounds %i, %a, "array index out of bounds" : memref<?x!idr.box<!R>, #idr.world>
    %w2 = idr.array.set %a[%k], %n, %w1 : memref<?x!idr.box<!R>, #idr.world>, !idr.box<!R>
    return %w2 : !idr.world
  }

  idr.func @printed(%ref: memref<!idr.box<!R>, #idr.world>, %s: !idr.str, %w: !idr.world) -> !idr.world attributes {no_inline} {
    %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<!R>, #idr.world> -> !idr.box<!R>
    %v = idr.world.new
    %v1 = idr.io.put_str %s, %v
    %n = idr.call @bump(%r) : (!idr.box<!R>) -> !idr.box<!R>
    %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<!R>, #idr.world>, !idr.box<!R>
    return %w2 : !idr.world
  }

  idr.func @callsIO(%ref: memref<!idr.box<!R>, #idr.world>, %s: !idr.str, %w: !idr.world) -> (i64, !idr.world) attributes {no_inline} {
    %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<!R>, #idr.world> -> !idr.box<!R>
    %z = idr.call @sneaky(%s) : (!idr.str) -> i64
    %n = idr.call @bump(%r) : (!idr.box<!R>) -> !idr.box<!R>
    %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<!R>, #idr.world>, !idr.box<!R>
    return %z, %w2 : i64, !idr.world
  }

  idr.func @inMatch(%ref: memref<!idr.box<!R>, #idr.world>, %b: i64, %w: !idr.world) -> !idr.world attributes {no_inline} {
    %r, %w1 = idr.array.get %ref[], %w : memref<!idr.box<!R>, #idr.world> -> !idr.box<!R>
    %w3 = idr.match_lit %b : i64 -> (!idr.world) {
    case 0 {
      %n = idr.call @bump(%r) : (!idr.box<!R>) -> !idr.box<!R>
      %w2 = idr.array.set %ref[], %n, %w1 : memref<!idr.box<!R>, #idr.world>, !idr.box<!R>
      idr.yield %w2 : !idr.world
    }
    default(%d: i64) {
      idr.yield %w1 : !idr.world
    }
    }
    return %w3 : !idr.world
  }

  idr.func @word(%ref: memref<i64, #idr.world>, %w: !idr.world) -> !idr.world attributes {no_inline} {
    %x, %w1 = idr.array.get %ref[], %w : memref<i64, #idr.world> -> i64
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    %w2 = idr.array.set %ref[], %y, %w1 : memref<i64, #idr.world>, i64
    return %w2 : !idr.world
  }
  // The program's root, which runs every function above on what it reads,
  // so that the optimizer keeps each and its checks are of the optimized
  // body; none is ever inlined.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w0 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %r = idr.con !idr.box<!R> @MkR(%x : i64, %x : i64)
    %ref, %w1 = idr.array.new [], %r, %w0 : !idr.box<!R> -> memref<!idr.box<!R>, #idr.world>
    %w2 = idr.call @update(%ref, %w1) : (memref<!idr.box<!R>, #idr.world>, !idr.world) -> !idr.world
    %one = arith.constant 1 : i64
    %zero = arith.constant 0 : i64
    %a, %w3 = idr.array.new [%one], %r, %w2 : !idr.box<!R> -> memref<?x!idr.box<!R>, #idr.world>
    %w4 = idr.call @updateAt(%a, %zero, %w3) : (memref<?x!idr.box<!R>, #idr.world>, i64, !idr.world) -> !idr.world
    %line, %w5 = idr.io.get_line %w4
    %w6 = idr.call @printed(%ref, %line, %w5) : (memref<!idr.box<!R>, #idr.world>, !idr.str, !idr.world) -> !idr.world
    %k, %w7 = idr.call @callsIO(%ref, %line, %w6) : (memref<!idr.box<!R>, #idr.world>, !idr.str, !idr.world) -> (i64, !idr.world)
    %w8 = idr.call @inMatch(%ref, %x, %w7) : (memref<!idr.box<!R>, #idr.world>, i64, !idr.world) -> !idr.world
    %words, %w9 = idr.array.new [], %x, %w8 : i64 -> memref<i64, #idr.world>
    %w10 = idr.call @word(%words, %w9) : (memref<i64, #idr.world>, !idr.world) -> !idr.world
    %w11 = idr.io.put_sint %k, %w10 : i64
    return %w11 : !idr.world
  }
}
