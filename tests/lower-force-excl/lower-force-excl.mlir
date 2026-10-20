// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,direct-calls,writes-nothing=@once,calls=@once:@one,calls=@once:@plus,calls-only=@once:[@one,@plus,@idris_rt_free_cell,@idris_rt_crash],crash-sites=@once:1' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// A memo cell nothing else holds is forced once, so nothing is memoized:
// its captures, or its value, move out of it, its memory goes, and the
// cell is never written. A cell in a label's state calls the label's
// function directly with its captures, after its memory is freed.
// Each state gives its value: the root forces a cell of each state, of
// the byte x it reads, @one's, @plus x's and a forced 2x, and then, for x
// of 0, a running one. The program, lowered and as written, prints 1,
// x + 1 and 2x, and crashes for 0, as the reference at the end (REF), with
// no cell, does (%differential, on 0, 1, 255 and the end of input).
// STDIN: \0000
// STDIN: \0001
// STDIN: \0377
// STDIN:
!Thunk = !idr.data<"Thunk">
#types = #idr.types<
  "Thunk" = memo [@one() label @one, @plus(i64) label @plus, @running() running, @forced(i64) forced]
>
idr.program @"force-excl" root(@Main.main) stage(owned) types #types {
  idr.func @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @plus(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func @once(%t: !idr.excl<!idr.box<!Thunk>>) -> i64 {
    %v = idr.borrow %t : !idr.excl<!idr.box<!Thunk>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!Thunk>> -> (i64) {
    case @one() {
      %k = idr.take %t : !idr.excl<!idr.box<!Thunk>> @one -> (!idr.excl<!idr.token>)
      idr.drop %k : !idr.excl<!idr.token>
      %y = idr.call @one() : () -> i64
      idr.yield %y : i64
    }
    case @plus(%x: i64) {
      %k:2 = idr.take %t : !idr.excl<!idr.box<!Thunk>> @plus -> (!idr.excl<!idr.token>, i64)
      idr.drop %k#0 : !idr.excl<!idr.token>
      %y = idr.call @plus(%k#1) : (i64) -> i64
      idr.yield %y : i64
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%f: i64) {
      %k:2 = idr.take %t : !idr.excl<!idr.box<!Thunk>> @forced -> (!idr.excl<!idr.token>, i64)
      idr.drop %k#0 : !idr.excl<!idr.token>
      idr.yield %k#1 : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %ko = idr.cell.new : !idr.cell<!idr.box<!Thunk>, @one>
    %to = idr.cell.init %ko : !idr.cell<!idr.box<!Thunk>, @one> () -> !idr.excl<!idr.box<!Thunk>>
    %a = idr.call @once(%to) : (!idr.excl<!idr.box<!Thunk>>) -> i64
    %kp = idr.cell.new : !idr.cell<!idr.box<!Thunk>, @plus>
    %tp = idr.cell.init %kp : !idr.cell<!idr.box<!Thunk>, @plus> (%x : i64) -> !idr.excl<!idr.box<!Thunk>>
    %b = idr.call @once(%tp) : (!idr.excl<!idr.box<!Thunk>>) -> i64
    %twice = arith.addi %x, %x : i64
    %kf = idr.cell.new : !idr.cell<!idr.box<!Thunk>, @forced>
    %tf = idr.cell.init %kf : !idr.cell<!idr.box<!Thunk>, @forced> (%twice : i64) -> !idr.excl<!idr.box<!Thunk>>
    %d = idr.call @once(%tf) : (!idr.excl<!idr.box<!Thunk>>) -> i64
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_sint %a, %w1 : i64
    %w3 = idr.io.put_char %nl, %w2
    %w4 = idr.io.put_sint %b, %w3 : i64
    %w5 = idr.io.put_char %nl, %w4
    %w6 = idr.io.put_sint %d, %w5 : i64
    %w7 = idr.io.put_char %nl, %w6
    %e = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      %kr = idr.cell.new : !idr.cell<!idr.box<!Thunk>, @running>
      %tr = idr.cell.init %kr : !idr.cell<!idr.box<!Thunk>, @running> () -> !idr.excl<!idr.box<!Thunk>>
      %r = idr.call @once(%tr) : (!idr.excl<!idr.box<!Thunk>>) -> i64
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
// REF: idr.program @ref root(@Main.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Main.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %x = arith.extui %c : i32 to i64
// REF:     %one = arith.constant 1 : i64
// REF:     %y = arith.addi %x, %one : i64
// REF:     %twice = arith.addi %x, %x : i64
// REF:     %nl = arith.constant 10 : i32
// REF:     %w2 = idr.io.put_sint %one, %w1 : i64
// REF:     %w3 = idr.io.put_char %nl, %w2
// REF:     %w4 = idr.io.put_sint %y, %w3 : i64
// REF:     %w5 = idr.io.put_char %nl, %w4
// REF:     %w6 = idr.io.put_sint %twice, %w5 : i64
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
