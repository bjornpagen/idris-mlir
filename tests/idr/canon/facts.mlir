// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=calls=@unused:@square,calls=@unused:@partial,\
// RUN: calls=@unused:@crashes,crashes-before-output=@across_computing,\
// RUN: crashes-before-output=@across_crashing,crashes-before-output=@across_given,\
// RUN: builds-nothing=@delayed_crash,crash-sites=@delayed_crash:2 -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --canonicalize --idr-expect=holds=no-heap-allocation=@across_computing -o /dev/null
// RUN: idris-mlir-opt %s --idr-canonicalize=test-convergence=true -o /dev/null
// NEEDS-ACCEPTANCE: that a canonicalizer without the program's symbol table keeps every call where it is and moves nothing across one, and keeps every unused call.
// Canonicalization moves code as the effects of each op answer. A call
// holds no effects of its own: what it does is its callee's, which a
// canonicalizer reads only when it is given the program's symbol table,
// as idr-optimize's is (optimize/case-of-case-calls.mlir moves output
// across a call of a pure callee there). This one has none, so a call may
// do anything: output stays after a call even of a callee that only
// computes, so @across_computing still builds the string it writes (the
// second RUN line), and nothing is ever written before a call, nor before
// a value that may crash, which moves only where it still runs on every
// path. Dead code removal reads the call alone too, so every unused call
// stays (idr-pure-calls drops those of pure callees). A callee that
// applies a closure it is given may do what that closure does, which
// nothing here knows: it may crash or never return.

!Maybe = !idr.data<"Maybe", plain [@Nothing(), @Just(i64)]>
idr.program @facts root(@root) stage(higher) {
  idr.func @square(%x: i64) -> i64 attributes {total, effects = #idr.effects<none>} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @partial(%x: i64) -> i64 attributes {effects = #idr.effects<diverge>} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @crashes(%x: i64) -> i64 attributes {total, effects = #idr.effects<crash>} {
    %r = idr.div signed %x, %x : i64
    return %r : i64
  }
  idr.func @applies(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {effects = #idr.effects<crash, diverge>} {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }

  // Unused calls stay, whatever their callees' effects (effects/queries.mlir
  // states the answers).
  idr.func @unused(%x: i64) {
    %a = idr.call @square(%x) : (i64) -> i64
    %c = idr.call @partial(%x) : (i64) -> i64
    %d = idr.call @crashes(%x) : (i64) -> i64
    return
  }

  // With the program's table, case-of-case would move the output into the
  // match across this call, which only computes, and write the number one
  // region shows; without one the call may do anything, and the output
  // stays after it. The match itself may crash, so it cannot move down
  // instead.
  idr.func @across_computing(%n: i64, %x: i64, %w: !idr.world) -> (!idr.world, i64) {
    %s = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      %t = idr.str.show signed %x : i64
      idr.yield %t : !idr.str
    }
    case 1 {
      %c = idr.constant "one" : !idr.str
      idr.yield %c : !idr.str
    }
    default {
      idr.crash "no"
      ub.unreachable
    }
    }
    %q = idr.call @square(%x) : (i64) -> i64
    %w1 = idr.io.put_str %s, %w
    return %w1, %q : !idr.world, i64
  }

  // Output stays after a call that may crash, or that applies a closure it
  // is given, which may: nothing is written before it.
  idr.func @across_crashing(%n: i64, %x: i64, %w: !idr.world) -> (!idr.world, i64) {
    %s = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      %t = idr.str.show signed %x : i64
      idr.yield %t : !idr.str
    }
    case 1 {
      %c = idr.constant "one" : !idr.str
      idr.yield %c : !idr.str
    }
    default {
      idr.crash "no"
      ub.unreachable
    }
    }
    %q = idr.call @crashes(%x) : (i64) -> i64
    %w1 = idr.io.put_str %s, %w
    return %w1, %q : !idr.world, i64
  }
  idr.func @across_given(%n: i64, %g: !idr.fn<(i64) -> (i64)>, %x: i64, %w: !idr.world) -> (!idr.world, i64) {
    %s = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      %t = idr.str.show signed %x : i64
      idr.yield %t : !idr.str
    }
    case 1 {
      %c = idr.constant "one" : !idr.str
      idr.yield %c : !idr.str
    }
    default {
      idr.crash "no"
      ub.unreachable
    }
    }
    %q = idr.call @applies(%g, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %w1 = idr.io.put_str %s, %w
    return %w1, %q : !idr.world, i64
  }

  // A match that may crash, which every region of a later match uses, moves
  // into each of them, where a match of it meets its constructor: it still
  // runs on every path, before anything it could hide.
  idr.func @delayed_crash(%c: i64, %n: i64) -> i64 {
    %p = idr.match_lit %c : i64 -> (!Maybe) {
    case 0 {
      %j = idr.con !Maybe @Just(%n : i64)
      idr.yield %j : !Maybe
    }
    default {
      idr.crash "no"
      ub.unreachable
    }
    }
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %a = idr.match %p : !Maybe -> (i64) {
      case @Nothing() {
        %one = arith.constant 1 : i64
        idr.yield %one : i64
      }
      case @Just(%y: i64) {
        idr.yield %y : i64
      }
      }
      idr.yield %a : i64
    }
    default {
      %b = idr.match %p : !Maybe -> (i64) {
      case @Nothing() {
        %two = arith.constant 2 : i64
        idr.yield %two : i64
      }
      case @Just(%y: i64) {
        %z = arith.addi %y, %y : i64
        idr.yield %z : i64
      }
      }
      idr.yield %b : i64
    }
    }
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
