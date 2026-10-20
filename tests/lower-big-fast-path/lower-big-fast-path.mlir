// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %s
// RUN: sed 's/root(@small)/root(@large)/' %s > %t.large.mlir
// RUN: idris-mlir -c %t.large.mlir -o %t.large.o
// RUN: %cc %t.large.o -o %t.large
// RUN: printf '4611686018427387903\n1\n' | %t.large | FileCheck %s --match-full-lines --check-prefix=UP
// RUN: printf -- '-4611686018427387904\n-1\n' | %t.large | FileCheck %s --match-full-lines --check-prefix=DOWN
// RUN: printf '18446744073709551616\n-18446744073709551615\n' | %t.large | FileCheck %s --match-full-lines --check-prefix=BACK
// RUN: printf '170141183460469231731687303715884105727\n1\n' | %t.large | FileCheck %s --match-full-lines --check-prefix=WIDE
// RUN: idris-mlir -c %s -o %t.small.o
// RUN: llvm-nm --undefined-only --format=just-symbols %t.small.o > %t.small.imports
// RUN: not grep -E '^_?(idris_rt_big|idris_rt_nat|_ZN2rt3big)' %t.small.imports
// RUN: llvm-nm --undefined-only --format=just-symbols %t.large.o > %t.large.imports
// RUN: grep -E '^_?_ZN2rt3big' %t.large.imports
// RUN: not grep -E '^_?idris_rt_big_add$' %t.large.imports
// A big or natural op is a call of the runtime's function for it, whose
// small case is inline in the runtime and whose large case is a call of
// its own: the op's arithmetic is the runtime's alone. idris-mlir joins
// the runtime's bitcode to the program and optimizes them together, so the
// small case is the program's code. Stated by what the object imports: a
// program whose operands are small by construction (integers narrower
// than the small range, results that fit) imports no big function of the
// runtime at all, so each small case is inline and its large case gone
// (the root @small); a program on bigs of any size (the root @large, which
// a sed of the root makes the program's) imports a large case, which is
// of the runtime's big namespace, and not the add's entry. It reads and shows its bigs through the
// runtime's own functions, which have no small case and which it may well
// import. A symbol is matched with and without the leading underscore an
// object format may write.
// Inline or not, each case computes what Integer and Nat say. On every
// one-byte input c the small root prints 2c, 0, c * c, 1 and c, as the
// reference at the end (REF), on words alone, does (%differential); and
// the large root's sum crosses the small range's edges both ways: up from
// its largest small value, 2^62 - 1, and down from its smallest, -2^62,
// back to a small value from two large ones, and on to 2^127.
// UP: 4611686018427387904
// DOWN: -4611686018427387905
// BACK: 1
// WIDE: 170141183460469231731687303715884105728
idr.program @"big-fast-path" root(@small) stage(higher) types #idr.types<> {
  idr.func @sum(%x: i32, %y: i32) -> i64 {
    %a = idr.big.from_sint %x : i32
    %b = idr.big.from_sint %y : i32
    %s = idr.big.add %a, %b
    %r = idr.big.to_int %s : i64
    return %r : i64
  }
  idr.func @difference(%x: i32, %y: i8) -> i64 {
    %a = idr.big.from_sint %x : i32
    %b = idr.big.from_uint %y : i8
    %s = idr.big.sub %a, %b
    %r = idr.big.to_int %s : i64
    return %r : i64
  }
  idr.func @product(%x: i32, %y: i16) -> i64 {
    %a = idr.big.from_sint %x : i32
    %b = idr.big.from_sint %y : i16
    %s = idr.big.mul %a, %b
    %r = idr.big.to_int %s : i64
    return %r : i64
  }
  idr.func @compared(%x: i32, %y: i32) -> i1 {
    %a = idr.big.from_sint %x : i32
    %b = idr.big.from_sint %y : i32
    %lt = idr.big.cmp lt %a, %b
    %eq = idr.big.cmp eq %a, %b
    %r = arith.xori %lt, %eq : i1
    return %r : i1
  }
  // The clamp of an Integer, one more, and its predecessor: all natural.
  idr.func @naturals(%x: i32) -> i64 {
    %a = idr.big.from_sint %x : i32
    %n = idr.nat.from_big %a
    %one = idr.constant !idr.nat #idr.big<1>
    %s = idr.big.add %n, %one : !idr.nat
    %p = idr.big.pred %s
    %i = idr.nat.to_big %p
    %r = idr.big.to_int %i : i64
    return %r : i64
  }
  idr.func @unknown(%a: !idr.big, %b: !idr.big) -> !idr.big {
    %s = idr.big.add %a, %b
    return %s : !idr.big
  }
  // The small root: each function on operands small by construction, its
  // result printed so that it is computed.
  idr.func @small(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %c8 = arith.trunci %c : i32 to i8
    %c16 = arith.trunci %c : i32 to i16
    %s = idr.call @sum(%c, %c) : (i32, i32) -> i64
    %d = idr.call @difference(%c, %c8) : (i32, i8) -> i64
    %p = idr.call @product(%c, %c16) : (i32, i16) -> i64
    %q = idr.call @compared(%c, %c) : (i32, i32) -> i1
    %n = idr.call @naturals(%c) : (i32) -> i64
    %qi = arith.extui %q : i1 to i64
    %w2 = idr.io.put_sint %s, %w1 : i64
    %w3 = idr.io.put_sint %d, %w2 : i64
    %w4 = idr.io.put_sint %p, %w3 : i64
    %w5 = idr.io.put_sint %qi, %w4 : i64
    %w6 = idr.io.put_sint %n, %w5 : i64
    return %w6 : !idr.world
  }
  // The large root: @unknown on two bigs read from input, any size.
  idr.func @large(%w: !idr.world) -> !idr.world {
    %l1, %w1 = idr.io.get_line %w
    %l2, %w2 = idr.io.get_line %w1
    %a = idr.big.from_str %l1
    %b = idr.big.from_str %l2
    %s = idr.call @unknown(%a, %b) : (!idr.big, !idr.big) -> !idr.big
    %t = idr.big.show %s
    %w3 = idr.io.put_str %t, %w2
    return %w3 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@small) stage(higher) types #idr.types<> {
// REF:   idr.func @small(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %x = arith.extui %c : i32 to i64
// REF:     %s = arith.addi %x, %x : i64
// REF:     %z = arith.constant 0 : i64
// REF:     %p = arith.muli %x, %x : i64
// REF:     %one = arith.constant 1 : i64
// REF:     %w2 = idr.io.put_sint %s, %w1 : i64
// REF:     %w3 = idr.io.put_sint %z, %w2 : i64
// REF:     %w4 = idr.io.put_sint %p, %w3 : i64
// REF:     %w5 = idr.io.put_sint %one, %w4 : i64
// REF:     %w6 = idr.io.put_sint %x, %w5 : i64
// REF:     return %w6 : !idr.world
// REF:   }
// REF: }
