// RUN: idris-mlir-opt %s --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// Before defunctionalization a force is strict like a call: it runs its
// suspension's code, which may crash or not return, so it may be delayed
// but neither moved, dropped nor merged with another force of the same
// cell, whatever the label it may find; what it may do is known only once
// it is a call of the sum's dispatch.
//
// The program forces, twice, a cell of @boom on the byte 0 and of @seven
// on any other: it crashes on 0 and writes 14 on any other byte, as the
// REFERENCE lines do, on 0, 1, 255 and the empty input.
// STDIN: \0000
// STDIN: \0001
// STDIN: \0377
// STDIN:
idr.program @"force-strict" root(@Prog.main) stage(higher) types #idr.types<> {
  idr.func @boom() -> i64 attributes {total} {
    idr.crash "boom"
    ub.unreachable
  }
  idr.func @seven() -> i64 attributes {total} {
    %c = arith.constant 7 : i64
    return %c : i64
  }
  idr.func @twice(%t: !idr.lazy<i64>) -> i64 {
    // expected-remark @below {{facts: [delay]}}
    %a = idr.force %t : !idr.lazy<i64> -> i64
    // expected-remark @below {{facts: [delay]}}
    %b = idr.force %t : !idr.lazy<i64> -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %t = idr.match_lit %c : i32 -> (!idr.lazy<i64>) {
    case 0 {
      %b = idr.suspend @boom() : () -> !idr.lazy<i64>
      idr.yield %b : !idr.lazy<i64>
    }
    default(%d: i32) {
      %s = idr.suspend @seven() : () -> !idr.lazy<i64>
      idr.yield %s : !idr.lazy<i64>
    }
    }
    %v = idr.call @twice(%t) : (!idr.lazy<i64>) -> i64
    %w2 = idr.io.put_sint %v, %w1 : i64
    return %w2 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@Prog.main) stage(higher) types #idr.types<> {
// REFERENCE:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REFERENCE:     %c, %w1 = idr.io.get_byte %w
// REFERENCE:     %w2 = idr.match_lit %c : i32 -> (!idr.world) {
// REFERENCE:     case 0 {
// REFERENCE:       idr.crash "boom"
// REFERENCE:       ub.unreachable
// REFERENCE:     }
// REFERENCE:     default(%d: i32) {
// REFERENCE:       %n = arith.constant 14 : i64
// REFERENCE:       %v = idr.io.put_sint %n, %w1 : i64
// REFERENCE:       idr.yield %v : !idr.world
// REFERENCE:     }
// REFERENCE:     }
// REFERENCE:     return %w2 : !idr.world
// REFERENCE:   }
// REFERENCE: }
