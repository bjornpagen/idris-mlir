// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,direct-calls,writes-nothing=@Loud.force,call-order=@Loud.force:[@idris_rt_inc,@shout],crash-sites=@Loud.force:1' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// A label that is `by_name` runs at every force, so the effect it reaches
// happens wherever its value is demanded: its case of the dispatch calls
// the label's function with the cell's captures and leaves the cell as it
// was, so lowering writes nothing to it. The label's function takes its
// capture owned, so the dispatch gives it a reference of its own first.
// So a cell forced twice runs its effect twice: the root forces it twice,
// and the program, lowered and as written, prints loud twice and exits
// with the sum of the two values, 2, as the reference at the end (REF),
// with no cell, does (%differential, on the one input, none, since it
// reads none).
// STDIN:
!Loud = !idr.data<"Loud">
#types = #idr.types<
  "Loud" = memo [@shout(!idr.str) label @shout by_name, @running() running, @forced(i64) forced]
>
idr.program @"force-by-name" root(@Main.main) stage(owned) types #types {
  idr.func @shout(%s: !idr.own<!idr.str>) -> i64 attributes {total} {
    %w = idr.world.new
    %v = idr.borrow %s : !idr.own<!idr.str>
    %w1 = idr.io.put_str borrow %v, %w
    idr.drop %s : !idr.own<!idr.str>
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @Loud.force(%t: !idr.q<many, borrow, !idr.box<!Loud>>) -> i64 {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!Loud>> -> (i64) {
    case @shout(%s: !idr.q<many, borrow, !idr.str>) {
      %o = idr.dup %s : !idr.q<many, borrow, !idr.str>
      %v = idr.call @shout(%o) : (!idr.own<!idr.str>) -> i64
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
  idr.func @Main.main() -> i64 {
    %s = idr.constant !idr.q<many, borrow, !idr.str> "loud"
    %o = idr.dup %s : !idr.q<many, borrow, !idr.str>
    %k = idr.cell.new : !idr.cell<!idr.box<!Loud>, @shout>
    %t = idr.cell.init %k : !idr.cell<!idr.box<!Loud>, @shout> (%o : !idr.own<!idr.str>)
    %b = idr.borrow %t : !idr.own<!idr.box<!Loud>>
    %v = idr.call @Loud.force(%b) : (!idr.q<many, borrow, !idr.box<!Loud>>) -> i64
    %b2 = idr.borrow %t : !idr.own<!idr.box<!Loud>>
    %u = idr.call @Loud.force(%b2) : (!idr.q<many, borrow, !idr.box<!Loud>>) -> i64
    idr.drop %t : !idr.own<!idr.box<!Loud>>
    %s2 = arith.addi %v, %u : i64
    return %s2 : i64
  }
}
// The reference:
// REF: idr.program @ref root(@Main.main) stage(higher) types #idr.types<> {
// REF:   idr.func @loud(%w: !idr.world) -> !idr.world {
// REF:     %l = arith.constant 108 : i32
// REF:     %o = arith.constant 111 : i32
// REF:     %u = arith.constant 117 : i32
// REF:     %d = arith.constant 100 : i32
// REF:     %w1 = idr.io.put_char %l, %w
// REF:     %w2 = idr.io.put_char %o, %w1
// REF:     %w3 = idr.io.put_char %u, %w2
// REF:     %w4 = idr.io.put_char %d, %w3
// REF:     return %w4 : !idr.world
// REF:   }
// REF:   idr.func @Main.main() -> i64 {
// REF:     %w = idr.world.new
// REF:     %w1 = idr.call @loud(%w) : (!idr.world) -> !idr.world
// REF:     %w2 = idr.call @loud(%w1) : (!idr.world) -> !idr.world
// REF:     %two = arith.constant 2 : i64
// REF:     return %two : i64
// REF:   }
// REF: }
