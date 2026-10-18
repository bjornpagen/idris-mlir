// NEEDS-ACCEPTANCE: each IO op's answers, reported by test-idr-facts, are none.
// RUN: idris-mlir-opt %s --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// Identical IO operations are neither merged nor removed, even unused: no
// IO op may be dropped, moved, delayed or merged, which is what dead code
// removal and CSE ask.

idr.program @io root(@io) stage(first) {
  idr.func @io(%w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    // expected-remark @below {{facts: []}}
    %w1 = idr.io.put_char %c, %w
    // expected-remark @below {{facts: []}}
    %w2 = idr.io.put_char %c, %w1
    // expected-remark @below {{facts: []}}
    %x, %w3 = idr.io.get_byte %w2
    // expected-remark @below {{facts: []}}
    %y, %w4 = idr.io.get_byte %w3
    return %w4 : !idr.world
  }

  // A forged world (a trusted library's unsafePerformIO) starts a chain of
  // its own; two of them are two, however alike, and neither is removed, nor
  // the IO on them: the effects order them where no world does.
  idr.func @forged(%c: i32) {
    // expected-remark @below {{facts: []}}
    %w = idr.world.new
    // expected-remark @below {{facts: []}}
    %w1 = idr.io.put_char %c, %w
    // expected-remark @below {{facts: []}}
    %v = idr.world.new
    // expected-remark @below {{facts: []}}
    %v1 = idr.io.put_char %c, %v
    return
  }
}
