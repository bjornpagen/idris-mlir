// RUN: idris-mlir-opt %s --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --cse --idr-expect=holds=crashes-before-output=@calls,crashes-before-output=@inline -o /dev/null
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// RUN: idris-mlir-opt %s --canonicalize --cse --control-flow-sink -o %t.sunk.mlir
// RUN: %differential %t.sunk.mlir %t.reference.mlir
// RUN: sed 's/case 0 {/case 1 {/' %t.reference.mlir > %t.wrong.mlir
// RUN: not %differential %s %t.wrong.mlir 2>&1 | FileCheck %s
// A crash ends the program's output: it writes the IO resource as well as
// the crash resource, so nothing moves output across it. A call of a
// function that may crash and do nothing else declares the same, from the
// one table of what each effect is: it may be delayed, as an inline crash
// may, but no output moves before it, and it moves before no output.
//
// The program writes B, then calls each function on the byte read, and
// writes what they return: the call's guard and the inline one crash on
// the byte 0, after the B and before either A, and on every other byte
// the run writes B, A, A and the byte twice. The REFERENCE lines write
// exactly that, with no call and no guard to move; the program means the
// same as written, and after the folds, CSE and control-flow sinking, on
// the byte 0, its neighbours, a letter, 255 and the empty input (read as
// 255). A reference that crashes on 1 instead is told apart on 0.
// CHECK: differential: effects-crash-call.mlir and {{.*}}wrong.mlir differ on '\0000'
// STDIN: \0000
// STDIN: \0001
// STDIN: x
// STDIN: \0377
// STDIN:
idr.program @"crash-call" root(@Prog.main) stage(first) {
  idr.func effects<crash> @crashes(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  idr.func @calls(%x: i64, %w: !idr.world) -> (i64, !idr.world) {
    // expected-remark @below {{facts: [delay]}}
    %y = idr.call @crashes(%x) effects<crash> : (i64) -> i64
    %c = arith.constant 65 : i32
    // expected-remark @below {{facts: []}}
    %w1 = idr.io.put_char %c, %w
    return %y, %w1 : i64, !idr.world
  }
  idr.func @inline(%x: i64, %w: !idr.world) -> (i64, !idr.world) {
    // expected-remark @below {{facts: [delay]}}
    %y = idr.check.nonzero %x, "division by zero" : i64
    %c = arith.constant 65 : i32
    // expected-remark @below {{facts: []}}
    %w1 = idr.io.put_char %c, %w
    return %y, %w1 : i64, !idr.world
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %b = arith.constant 66 : i32
    %w2 = idr.io.put_char %b, %w1
    %x = arith.extui %c : i32 to i64
    %y, %w3 = idr.call @calls(%x, %w2) : (i64, !idr.world) -> (i64, !idr.world)
    %z, %w4 = idr.call @inline(%x, %w3) : (i64, !idr.world) -> (i64, !idr.world)
    %w5 = idr.io.put_sint %y, %w4 : i64
    %w6 = idr.io.put_sint %z, %w5 : i64
    return %w6 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@Prog.main) stage(first) {
// REFERENCE:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REFERENCE:     %c, %w1 = idr.io.get_byte %w
// REFERENCE:     %b = arith.constant 66 : i32
// REFERENCE:     %w2 = idr.io.put_char %b, %w1
// REFERENCE:     %x = arith.extui %c : i32 to i64
// REFERENCE:     %w4 = idr.match_lit %x : i64 -> (!idr.world) {
// REFERENCE:     case 0 {
// REFERENCE:       idr.crash "division by zero"
// REFERENCE:       ub.unreachable
// REFERENCE:     }
// REFERENCE:     default(%d: i64) {
// REFERENCE:       %a = arith.constant 65 : i32
// REFERENCE:       %v1 = idr.io.put_char %a, %w2
// REFERENCE:       %v2 = idr.io.put_char %a, %v1
// REFERENCE:       %v3 = idr.io.put_sint %x, %v2 : i64
// REFERENCE:       %v4 = idr.io.put_sint %x, %v3 : i64
// REFERENCE:       idr.yield %v4 : !idr.world
// REFERENCE:     }
// REFERENCE:     }
// REFERENCE:     return %w4 : !idr.world
// REFERENCE:   }
// REFERENCE: }
