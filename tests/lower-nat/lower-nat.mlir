// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,signature=@naturals:(i64,i64,i64)->(i64,i64,i1,i64,i64,i64)' -o /dev/null
// A natural is the big it is: the same word at runtime, so a natural as an
// Integer is its operand itself. Its ops are calls of the runtime's big
// functions, whose small case joins the program with the runtime's
// bitcode (big-fast-path.mlir).
// Nat's zero and one are the small words of 0 and 1, as Integer's are:
// the runtime's encoding.
// A natural computes as the big it is: the root reads three lines, a, b
// and i, gives @naturals a + 1 (a natural not zero, as the predecessor
// asks), b as naturals (each an Integer clamped at 0) and i, and prints
// the six results. The program, lowered and as written, prints what the
// reference at the end (REF) computes on Integers, with no natural
// (%differential, on a + 1 at the small range's largest value, 2^62 - 1,
// and one past it, b of 0, 1 and large, and i below 0, 0 and large).
// STDIN: 0\n0\n0\n
// STDIN: 4611686018427387902\n1\n-1\n
// STDIN: 4611686018427387903\n0\n4611686018427387904\n
// STDIN: 5\n18446744073709551616\n-18446744073709551616\n
// STDIN: -3\n4611686018427387904\n7\n
// STDIN:
idr.program @nat root(@Prog.main) stage(first) {
  idr.func @naturals(%a: !idr.nat, %b: !idr.nat, %i: !idr.big)
      -> (!idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.big) {
    %s = idr.big.add %a, %b : !idr.nat
    %p = idr.big.mul %a, %b : !idr.nat
    %c = idr.big.cmp lt %a, %b : !idr.nat
    %d = idr.big.pred %a
    %n = idr.nat.from_big %i
    %e = idr.nat.to_big %a
    return %s, %p, %c, %d, %n, %e : !idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.big
  }
  idr.func @show(%n: !idr.nat, %w: !idr.world) -> !idr.world {
    %b = idr.nat.to_big %n
    %s = idr.big.show %b
    %w1 = idr.io.put_str %s, %w
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_char %nl, %w1
    return %w2 : !idr.world
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %la, %w1 = idr.io.get_line %w
    %lb, %w2 = idr.io.get_line %w1
    %li, %w3 = idr.io.get_line %w2
    %la_big = idr.big.from_str %la
    %lb_big = idr.big.from_str %lb
    %li_big = idr.big.from_str %li
    %a0 = idr.nat.from_big %la_big
    %one = idr.constant !idr.nat #idr.big<1>
    %a = idr.big.add %a0, %one : !idr.nat
    %b = idr.nat.from_big %lb_big
    %r:6 = idr.call @naturals(%a, %b, %li_big)
        : (!idr.nat, !idr.nat, !idr.big) -> (!idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.big)
    %w4 = idr.call @show(%r#0, %w3) : (!idr.nat, !idr.world) -> !idr.world
    %w5 = idr.call @show(%r#1, %w4) : (!idr.nat, !idr.world) -> !idr.world
    %c = arith.extui %r#2 : i1 to i64
    %w6 = idr.io.put_sint %c, %w5 : i64
    %nl = arith.constant 10 : i32
    %w7 = idr.io.put_char %nl, %w6
    %w8 = idr.call @show(%r#3, %w7) : (!idr.nat, !idr.world) -> !idr.world
    %w9 = idr.call @show(%r#4, %w8) : (!idr.nat, !idr.world) -> !idr.world
    %es = idr.big.show %r#5
    %w10 = idr.io.put_str %es, %w9
    %w11 = idr.io.put_char %nl, %w10
    return %w11 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) {
// REF:   idr.func @clamp(%x: !idr.big) -> !idr.big {
// REF:     %zero = idr.constant !idr.big #idr.big<0>
// REF:     %neg = idr.big.cmp lt %x, %zero
// REF:     %r = arith.select %neg, %zero, %x : !idr.big
// REF:     return %r : !idr.big
// REF:   }
// REF:   idr.func @show(%x: !idr.big, %w: !idr.world) -> !idr.world {
// REF:     %s = idr.big.show %x
// REF:     %w1 = idr.io.put_str %s, %w
// REF:     %nl = arith.constant 10 : i32
// REF:     %w2 = idr.io.put_char %nl, %w1
// REF:     return %w2 : !idr.world
// REF:   }
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %la, %w1 = idr.io.get_line %w
// REF:     %lb, %w2 = idr.io.get_line %w1
// REF:     %li, %w3 = idr.io.get_line %w2
// REF:     %ra = idr.big.from_str %la
// REF:     %rb = idr.big.from_str %lb
// REF:     %i = idr.big.from_str %li
// REF:     %a0 = idr.call @clamp(%ra) : (!idr.big) -> !idr.big
// REF:     %one = idr.constant !idr.big #idr.big<1>
// REF:     %a = idr.big.add %a0, %one
// REF:     %b = idr.call @clamp(%rb) : (!idr.big) -> !idr.big
// REF:     %s = idr.big.add %a, %b
// REF:     %p = idr.big.mul %a, %b
// REF:     %lt = idr.big.cmp lt %a, %b
// REF:     %n = idr.call @clamp(%i) : (!idr.big) -> !idr.big
// REF:     %w4 = idr.call @show(%s, %w3) : (!idr.big, !idr.world) -> !idr.world
// REF:     %w5 = idr.call @show(%p, %w4) : (!idr.big, !idr.world) -> !idr.world
// REF:     %c = arith.extui %lt : i1 to i64
// REF:     %w6 = idr.io.put_sint %c, %w5 : i64
// REF:     %nl = arith.constant 10 : i32
// REF:     %w7 = idr.io.put_char %nl, %w6
// REF:     %w8 = idr.call @show(%a0, %w7) : (!idr.big, !idr.world) -> !idr.world
// REF:     %w9 = idr.call @show(%n, %w8) : (!idr.big, !idr.world) -> !idr.world
// REF:     %w10 = idr.call @show(%a, %w9) : (!idr.big, !idr.world) -> !idr.world
// REF:     return %w10 : !idr.world
// REF:   }
// REF: }
