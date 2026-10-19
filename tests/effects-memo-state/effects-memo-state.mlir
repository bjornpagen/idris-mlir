// RUN: idris-mlir-opt %s --cse --canonicalize -o %t.merged.mlir
// RUN: %differential %s %t.merged.mlir
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// A memo cell is the one cell whose state changes while references to it
// live: its force, idr.memo.run, writes the memo state, and every read of a
// memo sum's value (its tag, a match on it, a field of it) reads it. So no
// pass merges two reads of one cell across a force, nor moves one across:
// the tag read before the force is the label's (0) and the one after it
// the forced state's (2), and CSE and the canonicalizer keep them two. A
// read of any other sum reads nothing, and its copies are merged freely.
// The program prints both tags of a cell of the byte read, then the forced
// value, the byte twice, as the REFERENCE lines do.
// STDIN: \0000
// STDIN: \0001
// STDIN: x
// STDIN: \0377
// STDIN:

!Lazy = !idr.data<"Lazy", memo [@twice(i64) label @twice, @running() running, @forced(i64) forced]>
idr.program @"memo-state" root(@Prog.main) stage(first) {
  idr.func @twice(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %t = idr.con !idr.box<!Lazy> @twice(%x : i64)
    %before = idr.tag %t : !idr.box<!Lazy>
    %v = idr.memo.run %t : !idr.box<!Lazy> @twice -> i64 {
    ^bb0(%xc: i64):
      %v0 = idr.call @twice(%xc) : (i64) -> i64
      idr.array.yield %v0, %v0 : i64, i64
    }
    %after = idr.tag %t : !idr.box<!Lazy>
    %sp = arith.constant 32 : i32
    %w2 = idr.io.put_sint %before, %w1 : i64
    %w3 = idr.io.put_char %sp, %w2
    %w4 = idr.io.put_sint %after, %w3 : i64
    %w5 = idr.io.put_char %sp, %w4
    %w6 = idr.io.put_sint %v, %w5 : i64
    return %w6 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@Prog.main) stage(first) {
// REFERENCE:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REFERENCE:     %c, %w1 = idr.io.get_byte %w
// REFERENCE:     %x = arith.extui %c : i32 to i64
// REFERENCE:     %v = arith.addi %x, %x : i64
// REFERENCE:     %s = idr.constant !idr.str "0 2 "
// REFERENCE:     %w2 = idr.io.put_str %s, %w1
// REFERENCE:     %w3 = idr.io.put_sint %v, %w2 : i64
// REFERENCE:     return %w3 : !idr.world
// REFERENCE:   }
// REFERENCE: }
