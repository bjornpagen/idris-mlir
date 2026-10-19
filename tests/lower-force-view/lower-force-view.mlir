// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,direct-calls,crash-sites=@Thunk.force:1,calls=@Thunk.force:@one,calls=@Thunk.force:@plus,calls-only=@Thunk.force:[@one,@plus,@idris_rt_crash],aligned-access' -o /dev/null
// A force is a call of its memo sum's dispatch, `<sum>.force`, which
// idr-defunctionalize makes: a match on the cell's state. A cell in a
// label's state is exchanged (idr.memo.run): its captures move out to the
// region, and it is marked running while the label's function is called
// there, so a force of it from inside the call finds it running and
// crashes, as a suspension that forces itself does; the value the region
// yields first is then stored in the cell, which is marked forced, and the
// one after it shared with the forcer. A forced cell's value is read with
// no call at all. So the dispatch calls each label's function directly, by
// name, and asks the runtime for nothing but the crash of a cell forced
// from inside its own force. The exchange writes the cell's header: the memo sum is a box of
// @one and @plus, then running and forced, so running is tag 2 and forced
// tag 3, each with the thunk kind, 1 << 24, the runtime's header words.
// What moves in is what a later force reads: the root forces a cell of
// @plus of the byte x it reads twice, the second time in its forced
// state, and one of @one, and then, for x of 0, one in the running state.
// The program, lowered and as written, prints x + 1 twice and 1, and
// crashes for 0, as the reference at the end (REF), with no cell, does
// (%differential, on 0, 1, 255 and the end of input).
// STDIN: \0000
// STDIN: \0001
// STDIN: \0377
// STDIN:
!Thunk = !idr.data<"Thunk", memo [@one() label @one, @plus(i64) label @plus, @running() running, @forced(i64) forced]>
idr.program @"force-view" root(@Main.main) stage(owned) {
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @plus(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func @Thunk.force(%t: !idr.q<many, borrow, !idr.box<!Thunk>>) -> i64 {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!Thunk>> -> (i64) {
    case @one() {
      %v = idr.memo.run %t : !idr.q<many, borrow, !idr.box<!Thunk>> @one -> i64 {
        %v0 = idr.call @one() : () -> i64
        idr.array.yield %v0, %v0 : i64, i64
      }
      idr.yield %v : i64
    }
    case @plus(%x: i64) {
      %v = idr.memo.run %t : !idr.q<many, borrow, !idr.box<!Thunk>> @plus -> i64 {
      ^bb0(%xc: i64):
        %v0 = idr.call @plus(%xc) : (i64) -> i64
        idr.array.yield %v0, %v0 : i64, i64
      }
      idr.yield %v : i64
    }
    case @running() {
      idr.crash "a suspension forced itself" loc("Main.idr":9:3)
      ub.unreachable
    }
    case @forced(%v: i64) {
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %k = idr.cell.new : !idr.cell<!idr.box<!Thunk>, @plus>
    %t = idr.cell.init %k : !idr.cell<!idr.box<!Thunk>, @plus> (%x : i64)
    %b = idr.borrow %t : !idr.own<!idr.box<!Thunk>>
    %v = idr.call @Thunk.force(%b) : (!idr.q<many, borrow, !idr.box<!Thunk>>) -> i64
    %b2 = idr.borrow %t : !idr.own<!idr.box<!Thunk>>
    %u = idr.call @Thunk.force(%b2) : (!idr.q<many, borrow, !idr.box<!Thunk>>) -> i64
    idr.drop %t : !idr.own<!idr.box<!Thunk>>
    %ko = idr.cell.new : !idr.cell<!idr.box<!Thunk>, @one>
    %to = idr.cell.init %ko : !idr.cell<!idr.box<!Thunk>, @one> ()
    %bo = idr.borrow %to : !idr.own<!idr.box<!Thunk>>
    %o = idr.call @Thunk.force(%bo) : (!idr.q<many, borrow, !idr.box<!Thunk>>) -> i64
    idr.drop %to : !idr.own<!idr.box<!Thunk>>
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_sint %v, %w1 : i64
    %w3 = idr.io.put_char %nl, %w2
    %w4 = idr.io.put_sint %u, %w3 : i64
    %w5 = idr.io.put_char %nl, %w4
    %w6 = idr.io.put_sint %o, %w5 : i64
    %w7 = idr.io.put_char %nl, %w6
    %e = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      %kr = idr.cell.new : !idr.cell<!idr.box<!Thunk>, @running>
      %tr = idr.cell.init %kr : !idr.cell<!idr.box<!Thunk>, @running> ()
      %br = idr.borrow %tr : !idr.own<!idr.box<!Thunk>>
      %r = idr.call @Thunk.force(%br) : (!idr.q<many, borrow, !idr.box<!Thunk>>) -> i64
      idr.drop %tr : !idr.own<!idr.box<!Thunk>>
      idr.yield %r : i64
    }
    default(%n: i64) {
      idr.yield %n : i64
    }
    }
    %w8 = idr.io.put_sint %e, %w7 : i64
    return %w8 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Main.main) stage(higher) {
// REF:   idr.func @Main.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %x = arith.extui %c : i32 to i64
// REF:     %one = arith.constant 1 : i64
// REF:     %y = arith.addi %x, %one : i64
// REF:     %nl = arith.constant 10 : i32
// REF:     %w2 = idr.io.put_sint %y, %w1 : i64
// REF:     %w3 = idr.io.put_char %nl, %w2
// REF:     %w4 = idr.io.put_sint %y, %w3 : i64
// REF:     %w5 = idr.io.put_char %nl, %w4
// REF:     %w6 = idr.io.put_sint %one, %w5 : i64
// REF:     %w7 = idr.io.put_char %nl, %w6
// REF:     %e = idr.match_lit %x : i64 -> (i64) {
// REF:     case 0 {
// REF:       idr.crash "a suspension forced itself"
// REF:       ub.unreachable
// REF:     }
// REF:     default(%n: i64) {
// REF:       idr.yield %n : i64
// REF:     }
// REF:     }
// REF:     %w8 = idr.io.put_sint %e, %w7 : i64
// REF:     return %w8 : !idr.world
// REF:   }
// REF: }
