// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,direct-calls,calls=@Tail.force:@idris_rt_persist_held,calls=@Prog.main:@Tail.force' -o /dev/null
// A lazy constant is a memo cell in static data, which its first force
// writes, once: its force is a call of the memo sum's dispatch, whose
// idr.memo.run exchanges the cell's state where it is. So its global is
// not constant, and its info word says the thunk kind (1 << 24) with its
// label's tag, here 0. Every other static cell stays constant, among them
// a constant stream whose tail is that cell: it holds the cell's address.
// After the force the dispatch asks the runtime to make what a static
// cell then holds persistent (idris_rt_persist_held), as static data is.
// The globals are the runtime's static data. The cell, once forced, gives
// the value that moved in: the root walks the stream as many steps as the
// byte it reads, each a force of the same static cell, and the program,
// lowered and as written, prints the sum of the heads it met, one more
// than the byte, as the reference at the end (REF) does (%differential,
// on 0, 1, 255 and the end of input).
// STDIN: \0000
// STDIN: \0001
// STDIN: \0377
// STDIN:
!Tail = !idr.data<"Tail">
!Stream = !idr.data<"Stream">
#types = #idr.types<
  "Stream" = plain [@Cons(i64, !idr.box<!idr.data<"Tail">>)],
  "Tail" = memo [@ones() label @ones, @running() running, @forced(!idr.box<!idr.data<"Stream">>) forced]
>
idr.program @"static-thunk" root(@Prog.main) stage(first) types #types {
  // ones = 1 :: ones: its tail is the thunk of the definition itself.
  idr.func @ones() -> !idr.box<!Stream> attributes {total} {
    %s = idr.constant !idr.box<!Stream> #idr.con<!Stream, @Cons, [1, #idr.con<!Tail, @ones, []>]>
    return %s : !idr.box<!Stream>
  }
  idr.func @Tail.force(%t: !idr.box<!Tail>) -> !idr.box<!Stream> {
    %r = idr.match %t : !idr.box<!Tail> -> (!idr.box<!Stream>) {
    case @ones() {
      %v = idr.memo.run %t : !idr.box<!Tail> @ones -> !idr.box<!Stream> {
        %v0 = idr.call @ones() : () -> !idr.box<!Stream>
        idr.array.yield %v0, %v0 : !idr.box<!Stream>, !idr.box<!Stream>
      }
      idr.yield %v : !idr.box<!Stream>
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.box<!Stream>) {
      idr.yield %v : !idr.box<!Stream>
    }
    }
    return %r : !idr.box<!Stream>
  }
  // The sum of the heads of the first n + 1 cells of %s.
  idr.func @walk(%s: !idr.box<!Stream>, %n: i64, %acc: i64) -> i64 {
    %h = idr.field %s : !idr.box<!Stream> @Cons[0] -> i64
    %more = arith.addi %acc, %h : i64
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %more : i64
    }
    default(%d: i64) {
      %t = idr.field %s : !idr.box<!Stream> @Cons[1] -> !idr.box<!Tail>
      %u = idr.call @Tail.force(%t) : (!idr.box<!Tail>) -> !idr.box<!Stream>
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %v = idr.call @walk(%u, %m, %more) : (!idr.box<!Stream>, i64, i64) -> i64
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %s = idr.call @ones() : () -> !idr.box<!Stream>
    %t = idr.field %s : !idr.box<!Stream> @Cons[1] -> !idr.box<!Tail>
    %u = idr.call @Tail.force(%t) : (!idr.box<!Tail>) -> !idr.box<!Stream>
    %zero = arith.constant 0 : i64
    %h = idr.call @walk(%u, %n, %zero) : (!idr.box<!Stream>, i64, i64) -> i64
    %w2 = idr.io.put_sint %h, %w1 : i64
    return %w2 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %n = arith.extui %c : i32 to i64
// REF:     %one = arith.constant 1 : i64
// REF:     %h = arith.addi %n, %one : i64
// REF:     %w2 = idr.io.put_sint %h, %w1 : i64
// REF:     return %w2 : !idr.world
// REF:   }
// REF: }
