// RUN: idris-mlir-opt %s --idr-effects --idr-expect=holds=effects=@divides:crash,effects=@makes:none,effects=@done:none,effects=@Lazy.force:crash,effects=@forces:crash,effects=@forces_twice:crash -o /dev/null
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// A memo sum stands to a suspension as a sum of closures stands to a
// closure, and a force is a call of the sum's dispatch, `<sum>.force`,
// which calls the function of each label it may find in the cell. So what
// a label may do flows to the forcer through that call, as any callee's
// does: the dispatch may crash when a label may, and when the cell is
// found running, a suspension that forces itself. Making a cell, of a label
// or of a state, runs nothing: the maker does no more than its own body
// does.
//
// The program forces a cell of the byte read twice: the first force runs
// the label, which divides the byte by itself, and the second finds the
// value; it crashes on 0 and writes 1 1 on every other byte, as the
// REFERENCE lines do, on 0, 1, 2, a letter, 255 and the empty input.
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: x
// STDIN: \0377
// STDIN:

!Lazy = !idr.data<"Lazy", memo [@divides(i64) label @divides, @running() running, @forced(i64) forced]>
idr.program @"memo-label" root(@Prog.main) stage(first) {
  idr.func @divides(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    %r = idr.divs %x, %y : i64
    return %r : i64
  }
  idr.func @makes(%x: i64) -> !idr.box<!Lazy> attributes {total} {
    %t = idr.con !idr.box<!Lazy> @divides(%x : i64)
    return %t : !idr.box<!Lazy>
  }
  idr.func @done(%x: i64) -> !idr.box<!Lazy> attributes {total} {
    %t = idr.con !idr.box<!Lazy> @forced(%x : i64)
    return %t : !idr.box<!Lazy>
  }
  idr.func @Lazy.force(%t: !idr.box<!Lazy>) -> i64 attributes {total} {
    %r = idr.match %t : !idr.box<!Lazy> -> (i64) {
    case @divides(%x: i64) {
      %v = idr.memo.run %t : !idr.box<!Lazy> @divides -> i64 {
      ^bb0(%xc: i64):
        %v0 = idr.call @divides(%xc) : (i64) -> i64
        idr.array.yield %v0, %v0 : i64, i64
      }
      idr.yield %v : i64
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: i64) {
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
  idr.func @forces(%x: i64) -> i64 attributes {total} {
    %t = idr.call @makes(%x) : (i64) -> !idr.box<!Lazy>
    %v = idr.call @Lazy.force(%t) : (!idr.box<!Lazy>) -> i64
    return %v : i64
  }
  idr.func @forces_twice(%x: i64) -> (i64, i64) attributes {total} {
    %t = idr.call @makes(%x) : (i64) -> !idr.box<!Lazy>
    %a = idr.call @Lazy.force(%t) : (!idr.box<!Lazy>) -> i64
    %b = idr.call @Lazy.force(%t) : (!idr.box<!Lazy>) -> i64
    return %a, %b : i64, i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %a, %b = idr.call @forces_twice(%x) : (i64) -> (i64, i64)
    %w2 = idr.io.put_sint %a, %w1 : i64
    %sp = arith.constant 32 : i32
    %w3 = idr.io.put_char %sp, %w2
    %w4 = idr.io.put_sint %b, %w3 : i64
    return %w4 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@Prog.main) stage(first) {
// REFERENCE:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REFERENCE:     %c, %w1 = idr.io.get_byte %w
// REFERENCE:     %w2 = idr.match_lit %c : i32 -> (!idr.world) {
// REFERENCE:     case 0 {
// REFERENCE:       idr.crash "division by zero"
// REFERENCE:       ub.unreachable
// REFERENCE:     }
// REFERENCE:     default(%d: i32) {
// REFERENCE:       %s = idr.constant !idr.str "1 1"
// REFERENCE:       %v = idr.io.put_str %s, %w1
// REFERENCE:       idr.yield %v : !idr.world
// REFERENCE:     }
// REFERENCE:     }
// REFERENCE:     return %w2 : !idr.world
// REFERENCE:   }
// REFERENCE: }
