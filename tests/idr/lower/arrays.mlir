// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=lowered,direct-calls -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=signature=@make:(i64,i8,!llvm.ptr)->(!llvm.ptr,i64),signature=@read:(!llvm.ptr,i64,i64)->(i8,!llvm.ptr),signature=@write:(!llvm.ptr,i64,i64,i8,!llvm.ptr)->(),signature=@length:(!llvm.ptr,i64)->index,signature=@bytes:(i64)->(!llvm.ptr,i64)' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=signature=@makeD:(i64,f64)->(!llvm.ptr,i64),signature=@readD:(!llvm.ptr,i64,i64)->f64,signature=@writeD:(!llvm.ptr,i64,i64,f64)->(),signature=@makeRef:(i8,!llvm.ptr)->!llvm.ptr,signature=@readRef:(!llvm.ptr)->(i8,!llvm.ptr),signature=@readRefD:(!llvm.ptr)->f64' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=reads-nothing=@length,crash-sites=@length:0,crash-sites=@read:1,crash-sites=@write:1,crash-sites=@readD:1,crash-sites=@writeD:1,crash-sites=@readRef:0,crash-sites=@takeRef:0' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=call-order=@make:[@idris_rt_array_new,@idris_rt_inc,@idris_rt_dec],loops=@make:1,calls=@read:@idris_rt_inc,calls=@write:@idris_rt_dec,calls=@readRef:@idris_rt_inc,never-calls=@takeRef:@idris_rt_inc,never-calls=@takeRef:@idris_rt_dec' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=calls-only=@makeD:[@idris_rt_array_new],loops=@makeD:1,calls-only=@readD:[@idris_rt_crash],calls-only=@writeD:[@idris_rt_crash],calls-only=@readRefD:[],calls-only=@length:[]' -o /dev/null
// RUN: idris-mlir-opt %t.mlir --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts --idr-expect=holds=in-llvm -o /dev/null
// NEEDS-ACCEPTANCE: the lowered signatures, the components of an array at a function boundary (the cell, then its dynamic sizes; a rank-0 array is its cell alone), with the runtime's symbols named as idris_rt.h declares them.
// An array a world orders is one runtime cell, allocated by
// idris_rt_array_new with the element layout in its header. At a function
// boundary its value is one pointer, the cell, then each size its type
// leaves dynamic: a size is a register, so taking it loads nothing, and
// the element at index 0 is computed from the cell where an access needs
// it, never passed. An IORef, an array of rank 0, is its cell alone. A
// new array writes the fill into every element, each taking a reference,
// and drops the fill's own. The guard of an index tests it against the
// size and crashes when it is out of bounds; the access then tests
// nothing. A read gives the element a reference of its own; a write drops
// the old element's and stores the new one. An element of one uncounted
// word (a double here) is a slot of its own, read and written at its
// address as every element is, and counts nothing. The world has no
// runtime form, so a function that only threads it returns nothing.
// A byte element takes one byte: the cell's header says the stride is 1
// (the tag bits) with no object slot, and kind array (4 << 24), the
// runtime's header word.
// An exchange, an update of the element whose region gives a new element
// back and the old one out, moves the old one out with the array's
// reference to it and stores the new one in its place: it counts nothing.
!Opt = !idr.data<"Opt", plain [@None(), @Some(!idr.str)]>
idr.program @arrays root(@root) stage(owned) {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 3 : i64
    %i = arith.constant 1 : i64
    %x = idr.con !idr.own<!Opt> @None()
    %a, %w1 = idr.call @make(%n, %x, %w) : (i64, !idr.own<!Opt>, !idr.world) -> (!idr.own<memref<?x!Opt, #idr.world>>, !idr.world)
    %b = idr.borrow %a : !idr.own<memref<?x!Opt, #idr.world>>
    %v, %w2 = idr.call @read(%b, %i, %w1) : (memref<?x!Opt, #idr.world>, i64, !idr.world) -> (!idr.own<!Opt>, !idr.world)
    %w3 = idr.call @write(%b, %i, %v, %w2) : (memref<?x!Opt, #idr.world>, i64, !idr.own<!Opt>, !idr.world) -> !idr.world
    %l = idr.call @length(%b) : (memref<?x!Opt, #idr.world>) -> index
    idr.drop %a : !idr.own<memref<?x!Opt, #idr.world>>
    %d = arith.constant 1.5 : f64
    %e, %w4 = idr.call @makeD(%n, %d, %w3) : (i64, f64, !idr.world) -> (!idr.own<memref<?xf64, #idr.world>>, !idr.world)
    %eb = idr.borrow %e : !idr.own<memref<?xf64, #idr.world>>
    %y, %w5 = idr.call @readD(%eb, %i, %w4) : (memref<?xf64, #idr.world>, i64, !idr.world) -> (f64, !idr.world)
    %w6 = idr.call @writeD(%eb, %i, %y, %w5) : (memref<?xf64, #idr.world>, i64, f64, !idr.world) -> !idr.world
    idr.drop %e : !idr.own<memref<?xf64, #idr.world>>
    return %w6 : !idr.world
  }
  idr.func @make(%n: i64, %x: !idr.own<!Opt>, %w: !idr.world) -> (!idr.own<memref<?x!Opt, #idr.world>>, !idr.world) {
    %a, %w1 = idr.array.new [%n], %x, %w : !idr.own<!Opt> -> !idr.own<memref<?x!Opt, #idr.world>>
    return %a, %w1 : !idr.own<memref<?x!Opt, #idr.world>>, !idr.world
  }
  idr.func @read(%a: memref<?x!Opt, #idr.world>, %i: i64, %w: !idr.world) -> (!idr.own<!Opt>, !idr.world) {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?x!Opt, #idr.world>
    %n = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %a, "array index out of bounds" : memref<?x!Opt, #idr.world>
    %v, %w1 = idr.array.get %a[%j], %w : memref<?x!Opt, #idr.world> -> !idr.own<!Opt>
    return %v, %w1 : !idr.own<!Opt>, !idr.world
  }
  idr.func @write(%a: memref<?x!Opt, #idr.world>, %i: i64, %y: !idr.own<!Opt>, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?x!Opt, #idr.world>
    %n = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %a, "array index out of bounds" : memref<?x!Opt, #idr.world>
    %w1 = idr.array.set %a[%j], %y, %w : memref<?x!Opt, #idr.world>, !idr.own<!Opt>
    return %w1 : !idr.world
  }
  idr.func @length(%a: memref<?x!Opt, #idr.world>) -> index {
    %c0 = arith.constant 0 : index
    %n = memref.dim %a, %c0 : memref<?x!Opt, #idr.world>
    return %n : index
  }
  idr.func @bytes(%n: i64, %w: !idr.world) -> (!idr.own<memref<?xi8, #idr.world>>, !idr.world) {
    %z = arith.constant 0 : i8
    %a, %w1 = idr.array.new [%n], %z, %w : i8 -> !idr.own<memref<?xi8, #idr.world>>
    return %a, %w1 : !idr.own<memref<?xi8, #idr.world>>, !idr.world
  }
  idr.func @makeD(%n: i64, %x: f64, %w: !idr.world) -> (!idr.own<memref<?xf64, #idr.world>>, !idr.world) {
    %a, %w1 = idr.array.new [%n], %x, %w : f64 -> !idr.own<memref<?xf64, #idr.world>>
    return %a, %w1 : !idr.own<memref<?xf64, #idr.world>>, !idr.world
  }
  idr.func @readD(%a: memref<?xf64, #idr.world>, %i: i64, %w: !idr.world) -> (f64, !idr.world) {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xf64, #idr.world>
    %n = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %a, "array index out of bounds" : memref<?xf64, #idr.world>
    %v, %w1 = idr.array.get %a[%j], %w : memref<?xf64, #idr.world> -> f64
    return %v, %w1 : f64, !idr.world
  }
  idr.func @writeD(%a: memref<?xf64, #idr.world>, %i: i64, %y: f64, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xf64, #idr.world>
    %n = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %a, "array index out of bounds" : memref<?xf64, #idr.world>
    %w1 = idr.array.set %a[%j], %y, %w : memref<?xf64, #idr.world>, f64
    return %w1 : !idr.world
  }
  idr.func @makeRef(%x: !idr.own<!Opt>, %w: !idr.world) -> (!idr.own<memref<!Opt, #idr.world>>, !idr.world) {
    %r, %w1 = idr.array.new [], %x, %w : !idr.own<!Opt> -> !idr.own<memref<!Opt, #idr.world>>
    return %r, %w1 : !idr.own<memref<!Opt, #idr.world>>, !idr.world
  }
  idr.func @readRef(%r: memref<!Opt, #idr.world>, %w: !idr.world) -> (!idr.own<!Opt>, !idr.world) {
    %v, %w1 = idr.array.get %r[], %w : memref<!Opt, #idr.world> -> !idr.own<!Opt>
    return %v, %w1 : !idr.own<!Opt>, !idr.world
  }
  idr.func @takeRef(%r: memref<!Opt, #idr.world>, %y: !idr.own<!Opt>, %w: !idr.world) -> (!idr.own<!Opt>, !idr.world) {
    %v, %w1 = idr.array.update %r[], %w {
    ^bb0(%old: !idr.own<!Opt>):
      idr.array.yield %y, %old : !idr.own<!Opt>, !idr.own<!Opt>
    } : memref<!Opt, #idr.world> -> !idr.own<!Opt>
    return %v, %w1 : !idr.own<!Opt>, !idr.world
  }
  idr.func @readRefD(%r: memref<f64, #idr.world>, %w: !idr.world) -> (f64, !idr.world) {
    %v, %w1 = idr.array.get %r[], %w : memref<f64, #idr.world> -> f64
    return %v, %w1 : f64, !idr.world
  }
}
