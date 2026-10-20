// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=stage=owned -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-rc,idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@walk})' -o /dev/null
// idr-rc counts what flows through every region op, and the owned stage's
// verifier, which runs after the pass, refuses a read through a view once
// the reference it borrows is gone: so that the pass's output verifies is
// the property. An owner stays alive while a view of it, tied to its
// shape, is read in a loop (@viewInLoop); an exclusive accumulator goes
// through an scf.for's inits and yields at its grade (@accumulate); the
// arms of an scf.if with an else and of an scf.index_switch, and the
// region of an array.update, each count what they take (@branches,
// @switch, @bump); and a self tail call that passes an element of its
// array is still a tail call, so the walk, a match as the frontend writes
// one, runs in constant stack (@walk).
// The root runs each of them on what the input byte sets: buffers of 0 to
// 3 strings, each filled before it is read, 0 to 3 doublings, both arms of
// the if, the three cases of the switch, and an element updated; every run
// prints what it printed before counting and leaves no cell live.
!B = !idr.data<"B">
#types = #idr.types<
  "B" = plain [@MkB(!idr.str)]
>
idr.program @"regions-counted" root(@root) stage(first) types #types {
  idr.func @make(%n: index) -> memref<?x!idr.str> {
    %b = memref.alloc(%n) : memref<?x!idr.str>
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    scf.for %i = %c0 to %n step %c1 {
      %s = idr.constant !idr.str "ab"
      memref.store %s, %b[%i] : memref<?x!idr.str>
    }
    return %b : memref<?x!idr.str>
  }
  idr.func @viewInLoop(%n: index) -> i64 {
    %b = idr.call @make(%n) : (index) -> memref<?x!idr.str>
    %t = idr.tie_shape %b dims(%n) : memref<?x!idr.str>
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %zero = arith.constant 0 : i64
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %zero) -> (i64) {
      %s = memref.load %t[%i] : memref<?x!idr.str>
      %l = idr.str.length %s
      %a = arith.addi %acc, %l : i64
      scf.yield %a : i64
    }
    return %r : i64
  }
  idr.func @accumulate(%n: index, %s: !idr.str) -> !idr.box<!B> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %init = idr.con !idr.box<!B> @MkB(%s : !idr.str)
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %init) -> (!idr.box<!B>) {
      %x = idr.field %acc : !idr.box<!B> @MkB[0] -> !idr.str
      %y = idr.str.append %x, %x
      %next = idr.con !idr.box<!B> @MkB(%y : !idr.str)
      scf.yield %next : !idr.box<!B>
    }
    return %r : !idr.box<!B>
  }
  idr.func @branches(%c: i1, %s: !idr.str, %t: !idr.str) -> !idr.str {
    %r = scf.if %c -> (!idr.str) {
      scf.yield %s : !idr.str
    } else {
      %u = idr.str.append %s, %t
      scf.yield %u : !idr.str
    }
    return %r : !idr.str
  }
  idr.func @switch(%k: index, %s: !idr.str) -> !idr.str {
    %r = scf.index_switch %k -> !idr.str
    case 0 {
      scf.yield %s : !idr.str
    }
    case 1 {
      %u = idr.str.reverse %s
      scf.yield %u : !idr.str
    }
    default {
      %e = idr.constant !idr.str ""
      scf.yield %e : !idr.str
    }
    return %r : !idr.str
  }
  idr.func @bump(%a: memref<?x!idr.box<!B>, #idr.world>, %i: i64, %w: !idr.world) -> !idr.world {
    %w1 = idr.array.update %a[%i], %w {
    ^bb0(%old: !idr.box<!B>):
      %x = idr.field %old : !idr.box<!B> @MkB[0] -> !idr.str
      %y = idr.str.append %x, %x
      %new = idr.con !idr.box<!B> @MkB(%y : !idr.str)
      idr.array.yield %new : !idr.box<!B>
    } : memref<?x!idr.box<!B>, #idr.world>
    return %w1 : !idr.world
  }
  idr.func @walk(%a: memref<?x!idr.str>, %i: index, %n: index, %acc: i64) -> i64 {
    %done = arith.cmpi uge, %i, %n : index
    %r = idr.match_lit %done : i1 -> (i64) {
    case true {
      idr.yield %acc : i64
    }
    default(%more: i1) {
      %s = memref.load %a[%i] : memref<?x!idr.str>
      %l = idr.str.length %s
      %a2 = arith.addi %acc, %l : i64
      %c1 = arith.constant 1 : index
      %j = arith.addi %i, %c1 : index
      %z = idr.call @walk(%a, %j, %n, %a2) : (memref<?x!idr.str>, index, index, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %c3 = arith.constant 3 : i64
    %c4 = arith.constant 4 : i64
    %zero = arith.constant 0 : i64
    %k = arith.remui %byte, %c4 : i64
    %q = arith.divui %byte, %c4 : i64
    %which = arith.remui %q, %c3 : i64
    %bit = arith.andi %byte, %c1 : i64
    %c = arith.cmpi ne, %bit, %zero : i64
    %n = arith.index_cast %k : i64 to index
    %v = idr.call @viewInLoop(%n) : (index) -> i64
    %s = idr.constant !idr.str "xyz"
    %t = idr.constant !idr.str "!"
    %acc = idr.call @accumulate(%n, %s) : (index, !idr.str) -> !idr.box<!B>
    %accs = idr.field %acc : !idr.box<!B> @MkB[0] -> !idr.str
    %accl = idr.str.length %accs
    %br = idr.call @branches(%c, %s, %t) : (i1, !idr.str, !idr.str) -> !idr.str
    %brl = idr.str.length %br
    %wi = arith.index_cast %which : i64 to index
    %sw = idr.call @switch(%wi, %s) : (index, !idr.str) -> !idr.str
    %w1 = idr.io.put_str %sw, %w0
    %one = idr.con !idr.box<!B> @MkB(%t : !idr.str)
    %arr, %w2 = idr.array.new [%c2], %one, %w1 : !idr.box<!B> -> memref<?x!idr.box<!B>, #idr.world>
    %i = idr.check.in_bounds %bit, %arr, "array index out of bounds" : memref<?x!idr.box<!B>, #idr.world>
    %w3 = idr.call @bump(%arr, %i, %w2) : (memref<?x!idr.box<!B>, #idr.world>, i64, !idr.world) -> !idr.world
    %e, %w4 = idr.array.get %arr[%i], %w3 : memref<?x!idr.box<!B>, #idr.world> -> !idr.box<!B>
    %es = idr.field %e : !idr.box<!B> @MkB[0] -> !idr.str
    %el = idr.str.length %es
    %buf = idr.call @make(%n) : (index) -> memref<?x!idr.str>
    %c0 = arith.constant 0 : index
    %wk = idr.call @walk(%buf, %c0, %n, %zero) : (memref<?x!idr.str>, index, index, i64) -> i64
    %w5 = idr.io.put_sint %v, %w4 : i64
    %w6 = idr.io.put_sint %accl, %w5 : i64
    %w7 = idr.io.put_sint %brl, %w6 : i64
    %w8 = idr.io.put_sint %el, %w7 : i64
    %w9 = idr.io.put_sint %wk, %w8 : i64
    return %w9 : !idr.world
  }
}
