// NEEDS-ACCEPTANCE: the memo cell is an idr.cell.new and its idr.cell.init (S3); the lowered calls are as before.
// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,direct-calls,writes-nothing=@Loud.force,call-order=@Loud.force:[@idris_rt_inc,@shout],crash-sites=@Loud.force:1' -o /dev/null
// NEEDS-ACCEPTANCE: the dispatch idr-defunctionalize makes of a memo sum whose label is by name: its label's case calls the function and neither enters nor settles the cell.
// A label that is `by_name` runs at every force, so the effect it reaches
// happens wherever its value is demanded: its case of the dispatch calls
// the label's function with the cell's captures and leaves the cell as it
// was, so lowering writes nothing to it. The label's function takes its
// capture owned, so the dispatch gives it a reference of its own first.
!Loud = !idr.data<"Loud", memo [@shout(!idr.str) label @shout by_name, @running() running, @forced(i64) forced]>
idr.program @"force-by-name" root(@Main.main) stage(owned) {
  idr.func @shout(%s: !idr.own<!idr.str>) -> i64 attributes {total} {
    %w = idr.world.new
    %v = idr.borrow %s : !idr.own<!idr.str>
    %w1 = idr.io.put_str %v, %w
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
    %s = idr.constant "loud" : !idr.str
    %o = idr.dup %s : !idr.q<many, borrow, !idr.str>
    %k = idr.cell.new : !idr.cell<!idr.box<!Loud>, @shout>
    %t = idr.cell.init %k : !idr.cell<!idr.box<!Loud>, @shout> (%o : !idr.own<!idr.str>)
    %b = idr.borrow %t : !idr.own<!idr.box<!Loud>>
    %v = idr.call @Loud.force(%b) : (!idr.q<many, borrow, !idr.box<!Loud>>) -> i64
    idr.drop %t : !idr.own<!idr.box<!Loud>>
    return %v : i64
  }
}
