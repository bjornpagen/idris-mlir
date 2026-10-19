// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-heap-allocation=@put_maybe,\
// RUN: builds-nothing=@field_of,no-heap-allocation=@past_effect,crashes-before-output=@both_effects,\
// RUN: grows-nothing=@nothing_to_meet:%s,no-heap-allocation=@crash_region,grows-nothing=@crash_region:%s,\
// RUN: builds-nothing=@match_of_match,matches=@match_of_match,builds-nothing=@uses_later,\
// RUN: builds-nothing=@nested,reads-fields=@nested,builds-nothing=@never_yields,reads-no-fields=@never_yields,\
// RUN: never-returns=@taken_never_completes,no-closures=@taken_never_completes -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@put_maybe,builds-nothing=@field_of,\
// RUN: no-heap-allocation=@past_effect,no-heap-allocation=@crash_region,builds-nothing=@match_of_match,\
// RUN: builds-nothing=@uses_later,builds-nothing=@nested,builds-nothing=@never_yields,reads-no-fields=@never_yields,\
// RUN: never-returns=@taken_never_completes,no-closures=@taken_never_completes -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=crashes-before-output=@root -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=reads-fields=@match_of_match -o /dev/null
// RUN: awk '/^  idr.func @nothing_to_meet/ { inside = 1 } inside && /^    %w1 = idr.io.put_str/ { printf "    %%unused = idr.str.length %%a\n"; inside = 0 } { print }' %s > %t.grown.mlir
// RUN: %status 1 idris-mlir-opt %t.grown.mlir --idr-expect=holds=grows-nothing=@nothing_to_meet:%s -o /dev/null
// BEFORE-DAG: expected no-heap-allocation: {{.*}} in @put_maybe
// BEFORE-DAG: expected builds-nothing: {{.*}} in @field_of
// BEFORE-DAG: expected no-heap-allocation: {{.*}} in @past_effect
// BEFORE-DAG: expected no-heap-allocation: {{.*}} in @crash_region
// BEFORE-DAG: expected builds-nothing: {{.*}} in @match_of_match
// BEFORE-DAG: expected builds-nothing: {{.*}} in @uses_later
// BEFORE-DAG: expected builds-nothing: {{.*}} in @nested
// BEFORE-DAG: expected builds-nothing: {{.*}} in @never_yields
// BEFORE-DAG: expected reads-no-fields: {{.*}} in @never_yields
// BEFORE-DAG: expected never-returns: {{.*}}@taken_never_completes
// BEFORE-DAG: expected no-closures: {{.*}} in @taken_never_completes
// Case-of-case: the single consumer of a match's result moves into every
// region that yields, when in some region it meets a value it folds or
// canonicalizes against. Each function states what is left: no string
// built only to be written (no heap allocation), no constructor built
// only to be taken apart, no output before what may crash, and where
// nothing folds, no copy of the consumer (the function grows nothing).
// The program, run on every byte, prints after the pass what it printed
// before it, crashes included. What canonicalize makes hold did not hold
// before it; the root writes before what may crash, @match_of_match reads
// no field once its matches are gone, and a copy of @nothing_to_meet with
// one more op than the file's grows: each of those fails.

// putStr (maybe "none" show m): each region writes its own string, and
// `show` becomes put_int.
!Maybe = !idr.data<"Maybe", plain [@Nothing(), @Just(i64)]>
!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.program @"case-of-case" root(@root) stage(higher) {
  idr.func @put_maybe(%m: !Maybe, %w: !idr.world) -> !idr.world {
    %s = idr.match %m : !Maybe -> (!idr.str) {
    case @Nothing() {
      %c = idr.constant !idr.str "none"
      idr.yield %c : !idr.str
    }
    case @Just(%x: i64) {
      %t = idr.str.show_sint %x : i64
      idr.yield %t : !idr.str
    }
    }
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }

  // A consumer that folds on a constructor: fst (if b then (1, 2) else p).
  idr.func @field_of(%b: i64, %p: !P) -> i64 {
    %q = idr.match_lit %b : i64 -> (!P) {
    case 0 {
      idr.yield %p : !P
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %two = arith.constant 2 : i64
      %c = idr.con !P @MkP(%one : i64, %two : i64)
      idr.yield %c : !P
    }
    }
    %f = idr.field %q : !P @MkP[0] -> i64
    return %f : i64
  }

  // The consumer does not move up past an op with effects, but a match free
  // of effects moves down past it to the consumer: show m is computed after
  // the character is written, and each region writes its own string.
  idr.func @past_effect(%m: !Maybe, %w: !idr.world) -> !idr.world {
    %s = idr.match %m : !Maybe -> (!idr.str) {
    case @Nothing() {
      %c = idr.constant !idr.str "none"
      idr.yield %c : !idr.str
    }
    case @Just(%x: i64) {
      %t = idr.str.show_sint %x : i64
      idr.yield %t : !idr.str
    }
    }
    %ch = arith.constant 65 : i32
    %w1 = idr.io.put_char %ch, %w
    %w2 = idr.io.put_str %s, %w1
    return %w2 : !idr.world
  }

  // A match with an effect (a region crashes) does not move past output, and
  // the consumer does not move up past it: both stay.
  idr.func @both_effects(%n: i64, %w: !idr.world) -> !idr.world {
    %s = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      %c = idr.constant !idr.str "zero"
      idr.yield %c : !idr.str
    }
    default(%d: i64) {
      idr.crash "no"
      ub.unreachable
    }
    }
    %ch = arith.constant 65 : i32
    %w1 = idr.io.put_char %ch, %w
    %w2 = idr.io.put_str %s, %w1
    return %w2 : !idr.world
  }

  // Nothing to meet: the consumer stays after the match, so nothing is
  // copied into the regions.
  idr.func @nothing_to_meet(%m: !Maybe, %a: !idr.str, %b: !idr.str,
                             %w: !idr.world) -> !idr.world {
    %s = idr.match %m : !Maybe -> (!idr.str) {
    case @Nothing() {
      idr.yield %a : !idr.str
    }
    case @Just(%x: i64) {
      idr.yield %b : !idr.str
    }
    }
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }

  // A region that crashes does not get the consumer: each other region
  // writes its own string, and nothing is copied into the crash.
  idr.func @crash_region(%n: i64, %w: !idr.world) -> !idr.world {
    %s = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      %t = idr.str.show_sint %n : i64
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
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }

  // A match of a match: the consumer is itself a match, and in each region it
  // meets a known constructor, so each region keeps only the case it takes.
  idr.func @match_of_match(%c: i64) -> i64 {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %p = idr.match_lit %c : i64 -> (!Maybe) {
    case 0 {
      %j = idr.con !Maybe @Just(%one : i64)
      idr.yield %j : !Maybe
    }
    default(%d: i64) {
      %n = idr.con !Maybe @Nothing()
      idr.yield %n : !Maybe
    }
    }
    %r = idr.match %p : !Maybe -> (i64) {
    case @Just(%x: i64) {
      idr.yield %x : i64
    }
    case @Nothing() {
      idr.yield %two : i64
    }
    }
    return %r : i64
  }

  // A consumer whose region uses a value made after the match cannot move up
  // into the match, where that value does not exist yet; the match, free of
  // effects, moves down to it instead, and there the consumer meets each
  // constructor: one match is left, of the literal. The product stays before
  // it: nothing in the region folds against it.
  idr.func @uses_later(%c: i64) -> i64 {
    %one = arith.constant 1 : i64
    %p = idr.match_lit %c : i64 -> (!Maybe) {
    case 0 {
      %j = idr.con !Maybe @Just(%one : i64)
      idr.yield %j : !Maybe
    }
    default(%d: i64) {
      %n = idr.con !Maybe @Nothing()
      idr.yield %n : !Maybe
    }
    }
    %k = arith.muli %c, %c : i64
    %r = idr.match %p : !Maybe -> (i64) {
    case @Just(%x: i64) {
      idr.yield %x : i64
    }
    case @Nothing() {
      idr.yield %k : i64
    }
    }
    return %r : i64
  }

  // The value a consumer meets may be one match deeper: no region of the
  // outer match yields a constructor, but one yields the result of an inner
  // match, whose regions do. fst (if b then (if c then (1, 2) else (3, 4))
  // else p): the consumer moves through both matches and folds against each
  // pair; only the read of p is left.
  idr.func @nested(%b: i64, %c: i64, %p: !P) -> i64 {
    %q = idr.match_lit %b : i64 -> (!P) {
    case 0 {
      %inner = idr.match_lit %c : i64 -> (!P) {
      case 0 {
        %one = arith.constant 1 : i64
        %two = arith.constant 2 : i64
        %x = idr.con !P @MkP(%one : i64, %two : i64)
        idr.yield %x : !P
      }
      default(%d: i64) {
        %three = arith.constant 3 : i64
        %four = arith.constant 4 : i64
        %y = idr.con !P @MkP(%three : i64, %four : i64)
        idr.yield %y : !P
      }
      }
      idr.yield %inner : !P
    }
    default(%d1: i64) {
      idr.yield %p : !P
    }
    }
    %f = idr.field %q : !P @MkP[0] -> i64
    return %f : i64
  }

  // A match none of whose regions yields never completes, so in a region of
  // another match nothing after it runs: the region ends in ub.unreachable
  // right after it. Here the consumer that case-of-case moved into that region
  // goes, and the region keeps only the match that crashes.
  idr.func @never_yields(%b: i64, %c: i64) -> i64 {
    %q = idr.match_lit %b : i64 -> (!P) {
    case 0 {
      %inner = idr.match_lit %c : i64 -> (!P) {
      case 0 {
        idr.crash "zero"
        ub.unreachable
      }
      default(%d: i64) {
        idr.crash "other"
        ub.unreachable
      }
      }
      idr.yield %inner : !P
    }
    default(%d1: i64) {
      %one = arith.constant 1 : i64
      %two = arith.constant 2 : i64
      %x = idr.con !P @MkP(%one : i64, %two : i64)
      idr.yield %x : !P
    }
    }
    %f = idr.field %q : !P @MkP[0] -> i64
    return %f : i64
  }

  // A match on a constant takes the one region the constant selects: when
  // that region crashes, the match never completes whatever the others
  // yield, and nothing after it runs, here a function body's apply and
  // return.
  idr.func @taken_never_completes(%f: !idr.fn<(i64) -> (i64)>) -> i64 {
    %t = arith.constant 1 : i64
    %r = idr.match_lit %t : i64 -> (i64) {
    case 0 {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    default(%d: i64) {
      idr.crash "taken"
      ub.unreachable
    }
    }
    %y = idr.apply %f(%r) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  idr.func @plus(%k: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %k, %x : i64
    return %y : i64
  }
  // The program's root runs every function above on what it reads: the
  // byte's low three bits pick which of the four that may crash runs last,
  // and the rest of it is their argument and the others'.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w0 = idr.io.get_byte %w
    %byte = arith.extui %c : i32 to i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %c3 = arith.constant 3 : i64
    %c8 = arith.constant 8 : i64
    %sel = arith.remui %byte, %c8 : i64
    %a = arith.divui %byte, %c8 : i64
    %odd = arith.remui %a, %c2 : i64
    %half = arith.divui %a, %c2 : i64
    %oddhalf = arith.remui %half, %c2 : i64
    %a1 = arith.addi %a, %c1 : i64
    %p = idr.con !P @MkP(%a : i64, %a1 : i64)
    %m = idr.match_lit %odd : i64 -> (!Maybe) {
    case 0 {
      %n = idr.con !Maybe @Nothing()
      idr.yield %n : !Maybe
    }
    default(%d: i64) {
      %j = idr.con !Maybe @Just(%a : i64)
      idr.yield %j : !Maybe
    }
    }
    %r0 = idr.call @match_of_match(%odd) : (i64) -> i64
    %w1 = idr.io.put_sint %r0, %w0 : i64
    %r1 = idr.call @uses_later(%a) : (i64) -> i64
    %w2 = idr.io.put_sint %r1, %w1 : i64
    %r2 = idr.call @nested(%odd, %oddhalf, %p) : (i64, i64, !P) -> i64
    %w3 = idr.io.put_sint %r2, %w2 : i64
    %r3 = idr.call @field_of(%oddhalf, %p) : (i64, !P) -> i64
    %w4 = idr.io.put_sint %r3, %w3 : i64
    %w5 = idr.call @put_maybe(%m, %w4) : (!Maybe, !idr.world) -> !idr.world
    %w6 = idr.call @past_effect(%m, %w5) : (!Maybe, !idr.world) -> !idr.world
    %x = idr.constant !idr.str "x"
    %y = idr.constant !idr.str "y"
    %w7 = idr.call @nothing_to_meet(%m, %x, %y, %w6) : (!Maybe, !idr.str, !idr.str, !idr.world) -> !idr.world
    %w8 = idr.match_lit %sel : i64 -> (!idr.world) {
    case 0 {
      %v = idr.call @both_effects(%a, %w7) : (i64, !idr.world) -> !idr.world
      idr.yield %v : !idr.world
    }
    case 1 {
      %k = arith.remui %a, %c3 : i64
      %v = idr.call @crash_region(%k, %w7) : (i64, !idr.world) -> !idr.world
      idr.yield %v : !idr.world
    }
    case 2 {
      %r = idr.call @never_yields(%odd, %half) : (i64, i64) -> i64
      %v = idr.io.put_sint %r, %w7 : i64
      idr.yield %v : !idr.world
    }
    case 3 {
      %f = idr.closure @plus(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      %r = idr.call @taken_never_completes(%f) : (!idr.fn<(i64) -> (i64)>) -> i64
      %v = idr.io.put_sint %r, %w7 : i64
      idr.yield %v : !idr.world
    }
    default(%d: i64) {
      idr.yield %w7 : !idr.world
    }
    }
    return %w8 : !idr.world
  }
}
