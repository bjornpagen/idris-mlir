// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce),idr-expect{holds=one-clone=@loop,one-clone=@count})' -o /dev/null
// RUN: sed 's/%n = arith.constant 5 : i64/%n = arith.constant 1000000 : i64/' %s > %t.long.mlir
// RUN: not cmp -s %s %t.long.mlir
// RUN: idris-mlir-opt %t.long.mlir --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce),idr-expect{holds=one-clone=@loop,one-clone=@count})' -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce))' -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: printf '\177' | %t | FileCheck %s --check-prefix=BELOW
// RUN: printf '\200' | %t | FileCheck %s --check-prefix=AT
// RUN: printf '\377' | %t | FileCheck %s --check-prefix=ABOVE
// Inside a recursive component a call keys only the positions passed
// unchanged along the recursion, and a lone number is never a key
// position.
// - loop n f x = if n == 0 then x else loop (n - 1) f (f x), called as
//   loop 5 f x with f a closure that captures a value read at run time.
//   The closure is passed unchanged along the recursion, so the copy is
//   keyed on it once and calls itself; the count goes down at every step,
//   so it keys nothing: one copy, not one per step. No count of steps
//   decides it: the second RUN line calls loop 1000000 f x, with as few
//   copies.
// - count acc n = count (acc + 1) (n - 1), called with a constant Integer
//   accumulator and a counter read at run time: the accumulator changes on
//   every iteration, so it keys nothing either, and every call of @count
//   reaches one function.
// Each function carries the location Emit gives it, its definition's
// name, by which a copy names what it was made from.
// The accumulator starts 128 below 2^62, where the runtime's small
// integers end, so the counts read from the input byte cross into big
// ones; the differential holds the optimized program to the one as written
// on every byte, each side of that edge, and the program prints 5k and
// 2^62 - 128 + k for the byte k: the last small integer, 2^62 - 1, at 127,
// 2^62 at 128 and 2^62 + 127 at 255.
// BELOW: {{^}}6354611686018427387903{{$}}
// AT: {{^}}6404611686018427387904{{$}}
// ABOVE: {{^}}12754611686018427388031{{$}}
idr.program @countdown root(@Main.main) stage(higher) types #idr.types<> {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %k : i64
    return %y : i64
  } loc("add")
  idr.func @loop(%n: i64, %f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %z = idr.call @loop(%m, %f, %y) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  } loc("loop")
  idr.func @count(%acc: !idr.big, %n: i64) -> !idr.big attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.big) {
    case 0 {
      idr.yield %acc : !idr.big
    }
    default(%d: i64) {
      %one = idr.constant !idr.big #idr.big<1>
      %c1 = arith.constant 1 : i64
      %a = idr.big.add %acc, %one
      %m = arith.subi %n, %c1 : i64
      %x = idr.call @count(%a, %m) : (!idr.big, i64) -> !idr.big
      idr.yield %x : !idr.big
    }
    }
    return %r : !idr.big
  } loc("count")
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %k = arith.extui %c : i32 to i64
    %f = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %n = arith.constant 5 : i64
    %zero = arith.constant 0 : i64
    %r = idr.call @loop(%n, %f, %zero) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    %acc = idr.constant !idr.big #idr.big<4611686018427387776>
    %s = idr.call @count(%acc, %k) : (!idr.big, i64) -> !idr.big
    %t = idr.big.show %s
    %w3 = idr.io.put_str %t, %w2
    return %w3 : !idr.world
  } loc("Main.main")
}
