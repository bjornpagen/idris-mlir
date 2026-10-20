// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=calls=@unused:@square,calls=@unused:@partial,\
// RUN: calls=@unused:@crashes,crashes-before-output=@across_computing,\
// RUN: crashes-before-output=@across_crashing,crashes-before-output=@across_given,\
// RUN: builds-nothing=@delayed_crash,crash-sites=@delayed_crash:2 -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --canonicalize --idr-expect=holds=no-heap-allocation=@across_computing -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=builds-nothing=@delayed_crash,crash-sites=@delayed_crash:2' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=crashes-before-output=@root' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=crash-sites=@delayed_crash:1' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=crash-sites=@delayed_crash:3' -o /dev/null
// BEFORE-DAG: expected builds-nothing: {{.*}}@delayed_crash
// BEFORE-DAG: expected crash-sites: {{.*}}@delayed_crash
// Canonicalization moves code as the effects of each op answer. A call
// does what its own effects say, which idr-effects writes from its
// callee's (optimize-case-of-case-calls moves output across a call of
// a pure callee once it has). No pass has run here, so every call holds
// the effects a call has until one does, anything: output stays after a
// call even of a callee that only computes, so @across_computing still
// builds the string it writes (the second RUN line), and nothing is ever
// written before a call, nor before a value that may crash, which moves
// only where it still runs on every path. Dead code removal reads the call
// alone too, so every unused call stays. A callee that applies a closure
// it is given may do what that closure does, which nothing here knows: it
// may write, crash or never return.
// CHECK: expected no-heap-allocation: idr.str.show_sint {{.*}} in @across_computing
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it; the root writes before what may crash,
// and @delayed_crash's count of crash sites is exactly 2.

!Maybe = !idr.data<"Maybe">
#types = #idr.types<
  "Maybe" = plain [@Nothing(), @Just(i64)]
>
idr.program @facts root(@root) stage(higher) types #types {
  idr.func effects<none> @square(%x: i64) -> i64 attributes {total} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func effects<diverge> @partial(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func effects<crash> @crashes(%x: i64) -> i64 attributes {total} {
    %r = idr.divs %x, %x : i64
    return %r : i64
  }
  idr.func @applies(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }

  // Unused calls stay, whatever their callees' effects (effects-queries
  // states the answers).
  idr.func @unused(%x: i64) {
    %a = idr.call @square(%x) : (i64) -> i64
    %c = idr.call @partial(%x) : (i64) -> i64
    %d = idr.call @crashes(%x) : (i64) -> i64
    return
  }

  // Once the call holds its callee's effects, case-of-case would move the
  // output into the match across it, since it only computes, and write the
  // number one region shows; holding none yet, it may do anything, and the
  // output stays after it. The match itself may crash, so it cannot move
  // down instead.
  idr.func @across_computing(%n: i64, %x: i64, %w: !idr.world) -> (!idr.world, i64) {
    %s = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      %t = idr.str.show_sint %x : i64
      idr.yield %t : !idr.str
    }
    case 1 {
      %c = idr.constant !idr.str "one"
      idr.yield %c : !idr.str
    }
    default(%d: i64) {
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
      %t = idr.str.show_sint %x : i64
      idr.yield %t : !idr.str
    }
    case 1 {
      %c = idr.constant !idr.str "one"
      idr.yield %c : !idr.str
    }
    default(%d: i64) {
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
      %t = idr.str.show_sint %x : i64
      idr.yield %t : !idr.str
    }
    case 1 {
      %c = idr.constant !idr.str "one"
      idr.yield %c : !idr.str
    }
    default(%d: i64) {
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
    default(%d: i64) {
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
    default(%d1: i64) {
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
  idr.func @plus(%k: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %k, %x : i64
    return %y : i64
  }
  // The program's root runs the functions above on what it reads: the
  // byte's low two bits pick one, and the rest of it gives its choice
  // (0, 1, or 2, which crashes) and its number, from 1: @crashes divides by
  // it, and division is by a number that is not zero. @unused runs on that
  // number first.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c2 = arith.constant 2 : i64
    %c3 = arith.constant 3 : i64
    %c4 = arith.constant 4 : i64
    %sel = arith.remui %byte, %c4 : i64
    %a = arith.divui %byte, %c4 : i64
    %n = arith.remui %a, %c3 : i64
    %x0 = arith.divui %a, %c3 : i64
    %c1 = arith.constant 1 : i64
    %x = arith.addi %x0, %c1 : i64
    %w9 = idr.match_lit %sel : i64 -> (!idr.world) {
    case 0 {
      %w1, %q = idr.call @across_computing(%n, %x, %w0) : (i64, i64, !idr.world) -> (!idr.world, i64)
      %w2 = idr.io.put_sint %q, %w1 : i64
      idr.yield %w2 : !idr.world
    }
    case 1 {
      %w1, %q = idr.call @across_crashing(%n, %x, %w0) : (i64, i64, !idr.world) -> (!idr.world, i64)
      %w2 = idr.io.put_sint %q, %w1 : i64
      idr.yield %w2 : !idr.world
    }
    case 2 {
      %g = idr.closure @plus(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      %w1, %q = idr.call @across_given(%n, %g, %x, %w0) : (i64, !idr.fn<(i64) -> (i64)>, i64, !idr.world) -> (!idr.world, i64)
      %w2 = idr.io.put_sint %q, %w1 : i64
      idr.yield %w2 : !idr.world
    }
    default(%d: i64) {
      idr.call @unused(%x) : (i64) -> ()
      %c = arith.remui %a, %c2 : i64
      %h = arith.divui %a, %c2 : i64
      %r = idr.call @delayed_crash(%c, %h) : (i64, i64) -> i64
      %w2 = idr.io.put_sint %r, %w0 : i64
      idr.yield %w2 : !idr.world
    }
    }
    return %w9 : !idr.world
  }
}
