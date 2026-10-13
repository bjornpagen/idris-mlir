// RUN: idris-mlir-opt %s --pass-pipeline="builtin.module(idr-effects, idr-round-facts, idr.func(idr-identity), symbol-dce)" | FileCheck %s --implicit-check-not=@weaken --implicit-check-not=@same --implicit-check-not=@carry --implicit-check-not=@second
// RUN: idris-mlir-opt %s --pass-pipeline="builtin.module(idr-effects, idr-round-facts, idr.func(idr-identity), idr-expect{holds=not-called=@weaken,not-called=@weakenTerm,not-called=@weakenUnder,not-called=@weakenTree,not-called=@weakenForest,not-called=@same,not-called=@carry,not-called=@second})" -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline="builtin.module(idr-effects, idr-round-facts, idr.func(idr-identity))" -o %t.once.mlir
// RUN: idris-mlir-opt %t.once.mlir --pass-pipeline="builtin.module(idr-round-facts, idr.func(idr-identity))" -o %t.twice.mlir
// RUN: idris-mlir-opt %t.once.mlir -o %t.again.mlir
// RUN: cmp %t.again.mlir %t.twice.mlir
// A function that only rebuilds its argument
// gives it back, and every call of it becomes the argument; symbol-dce then
// erases it. Fin's weaken (FS of the weakened predecessor, on naturals);
// the weakening of a term to a larger scope, which rebuilds every node and
// weakens each variable with weaken; the same with a count it carries and
// never gives back; a tree and a forest weakened by mutual recursion, a
// region Idris proved is never taken among them; a function of a linear
// argument, whose call becomes the argument's one use; and one that passes
// its argument on whole, counting down another, which Idris proved ends;
// and one of two arguments of the type it gives back, whose calls become
// that argument and not the other. A function that calls itself on its
// whole argument without that proof, counting down or not, is not known to
// return and keeps its calls, as do one that crashes on a path, one that
// gives back zero whatever it gets, one that swaps a node's children, and
// one that gives back its argument only if the swapping one did: the
// assumption about the swapping one goes, and the one that rests on it
// goes with it. Run again on what it leaves, the pass changes nothing.
// CHECK-LABEL: idr.func private @loops(
// CHECK-LABEL: idr.func private @drift(
// CHECK-LABEL: idr.func private @crashes(
// CHECK-LABEL: idr.func private @zero(
// CHECK-LABEL: idr.func private @flip(
// CHECK-LABEL: idr.func private @leans(
// CHECK-LABEL: idr.func @main(
// CHECK-SAME: %[[T:[^:]*]]: !Term, %[[F:[^:]*]]: !Forest, %[[I:[^:]*]]: !idr.nat, %[[D:[^:]*]]: !idr.nat, %[[K:[^:]*]]: i64)
// CHECK: %[[FL:.*]] = idr.lin.enter %[[F]]
// CHECK: %[[FU:.*]] = idr.lin.use %[[FL]]
// CHECK: %[[F3:.*]] = call @loops(%[[F]])
// CHECK: %[[F4:.*]] = call @crashes(%[[F]])
// CHECK: %[[Z:.*]] = call @zero(%[[I]])
// CHECK: %[[S:.*]] = call @flip(%[[T]])
// CHECK: %[[R:.*]] = call @drift(%[[K]], %[[F]])
// CHECK: %[[L:.*]] = call @leans(%[[T]])
// CHECK: return %[[T]], %[[T]], %[[F]], %[[I]], %[[FU]], %[[F3]], %[[F4]], %[[Z]], %[[S]], %[[F]], %[[R]], %[[L]], %[[F]] :
module {
  idr.data @Term box {
    idr.ctor @Var (!idr.nat)
    idr.ctor @App (!idr.box<@Term>, !idr.box<@Term>)
    idr.ctor @Lam (!idr.box<@Term>)
    idr.ctor @Lit (!idr.big)
  }
  idr.data @Tree box {
    idr.ctor @Leaf (!idr.nat)
    idr.ctor @Node (!idr.box<@Forest>)
  }
  idr.data @Forest box {
    idr.ctor @Done ()
    idr.ctor @More (!idr.box<@Tree>, !idr.box<@Forest>)
  }
  // weaken FZ = FZ; weaken (FS k) = FS (weaken k)
  idr.func private @weaken(%i: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %i : !idr.nat -> (!idr.nat) {
    case #idr.big<"0"> {
      %z = idr.constant #idr.big<"0"> : !idr.nat
      idr.yield %z : !idr.nat
    }
    default {
      %k = idr.big.pred %i
      %w = idr.call @weaken(%k) : (!idr.nat) -> !idr.nat
      %one = idr.constant #idr.big<"1"> : !idr.nat
      %s = idr.big.add %w, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }
  idr.func private @weakenTerm(%t: !idr.box<@Term>) -> !idr.box<@Term> attributes {total} {
    %r = idr.match %t : !idr.box<@Term> -> (!idr.box<@Term>) {
    case @Var(%i: !idr.nat) {
      %j = idr.call @weaken(%i) : (!idr.nat) -> !idr.nat
      %v = idr.con @Term::@Var(%j) : (!idr.nat) -> !idr.box<@Term>
      idr.yield %v : !idr.box<@Term>
    }
    case @App(%f: !idr.box<@Term>, %a: !idr.box<@Term>) {
      %f2 = idr.call @weakenTerm(%f) : (!idr.box<@Term>) -> !idr.box<@Term>
      %a2 = idr.call @weakenTerm(%a) : (!idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@App(%f2, %a2) : (!idr.box<@Term>, !idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    case @Lam(%b: !idr.box<@Term>) {
      %b2 = idr.call @weakenTerm(%b) : (!idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@Lam(%b2) : (!idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    case @Lit(%x: !idr.big) {
      %c = idr.con @Term::@Lit(%x) : (!idr.big) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    }
    return %r : !idr.box<@Term>
  }
  // The count goes one up under each binder, and is never given back.
  idr.func private @weakenUnder(%d: !idr.nat, %t: !idr.box<@Term>) -> !idr.box<@Term> attributes {total} {
    %r = idr.match %t : !idr.box<@Term> -> (!idr.box<@Term>) {
    case @Var(%i: !idr.nat) {
      %j = idr.call @weaken(%i) : (!idr.nat) -> !idr.nat
      %v = idr.con @Term::@Var(%j) : (!idr.nat) -> !idr.box<@Term>
      idr.yield %v : !idr.box<@Term>
    }
    case @App(%f: !idr.box<@Term>, %a: !idr.box<@Term>) {
      %f2 = idr.call @weakenUnder(%d, %f) : (!idr.nat, !idr.box<@Term>) -> !idr.box<@Term>
      %a2 = idr.call @weakenUnder(%d, %a) : (!idr.nat, !idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@App(%f2, %a2) : (!idr.box<@Term>, !idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    case @Lam(%b: !idr.box<@Term>) {
      %one = idr.constant #idr.big<"1"> : !idr.nat
      %d1 = idr.big.add %d, %one : !idr.nat
      %b2 = idr.call @weakenUnder(%d1, %b) : (!idr.nat, !idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@Lam(%b2) : (!idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    case @Lit(%x: !idr.big) {
      idr.yield %t : !idr.box<@Term>
    }
    }
    return %r : !idr.box<@Term>
  }
  idr.func private @weakenTree(%t: !idr.box<@Tree>) -> !idr.box<@Tree> attributes {total} {
    %r = idr.match %t : !idr.box<@Tree> -> (!idr.box<@Tree>) {
    case @Leaf(%i: !idr.nat) {
      // Idris proved a leaf's index is never zero.
      %l = idr.match_lit %i : !idr.nat -> (!idr.box<@Tree>) {
      case #idr.big<"0"> {
        ub.unreachable
      }
      default {
        %j = idr.call @weaken(%i) : (!idr.nat) -> !idr.nat
        %v = idr.con @Tree::@Leaf(%j) : (!idr.nat) -> !idr.box<@Tree>
        idr.yield %v : !idr.box<@Tree>
      }
      }
      idr.yield %l : !idr.box<@Tree>
    }
    case @Node(%f: !idr.box<@Forest>) {
      %f2 = idr.call @weakenForest(%f) : (!idr.box<@Forest>) -> !idr.box<@Forest>
      %v = idr.con @Tree::@Node(%f2) : (!idr.box<@Forest>) -> !idr.box<@Tree>
      idr.yield %v : !idr.box<@Tree>
    }
    }
    return %r : !idr.box<@Tree>
  }
  idr.func private @weakenForest(%f: !idr.box<@Forest>) -> !idr.box<@Forest> attributes {total} {
    %r = idr.match %f : !idr.box<@Forest> -> (!idr.box<@Forest>) {
    case @Done() {
      %v = idr.con @Forest::@Done() : () -> !idr.box<@Forest>
      idr.yield %v : !idr.box<@Forest>
    }
    case @More(%t: !idr.box<@Tree>, %rest: !idr.box<@Forest>) {
      %t2 = idr.call @weakenTree(%t) : (!idr.box<@Tree>) -> !idr.box<@Tree>
      %rest2 = idr.call @weakenForest(%rest) : (!idr.box<@Forest>) -> !idr.box<@Forest>
      %v = idr.con @Forest::@More(%t2, %rest2) : (!idr.box<@Tree>, !idr.box<@Forest>) -> !idr.box<@Forest>
      idr.yield %v : !idr.box<@Forest>
    }
    }
    return %r : !idr.box<@Forest>
  }
  // A linear argument: the match takes it apart, or gives it back.
  idr.func private @same(%x: !idr.lin<!idr.box<@Forest>>) -> !idr.box<@Forest> attributes {total} {
    %r = idr.match %x : !idr.lin<!idr.box<@Forest>> -> (!idr.box<@Forest>) {
    case @Done() {
      %v = idr.con @Forest::@Done() : () -> !idr.box<@Forest>
      idr.yield %v : !idr.box<@Forest>
    }
    default(%back: !idr.lin<!idr.box<@Forest>>) {
      %v = idr.lin.use %back : !idr.lin<!idr.box<@Forest>>
      idr.yield %v : !idr.box<@Forest>
    }
    }
    return %r : !idr.box<@Forest>
  }
  // Counts n down, passing x on whole each time; Idris proved it ends.
  idr.func private @carry(%n: i64, %x: !idr.box<@Forest>) -> !idr.box<@Forest> attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.box<@Forest>) {
    case 0 {
      idr.yield %x : !idr.box<@Forest>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %y = idr.call @carry(%m, %x) : (i64, !idr.box<@Forest>) -> !idr.box<@Forest>
      idr.yield %y : !idr.box<@Forest>
    }
    }
    return %r : !idr.box<@Forest>
  }
  // Calls itself on its whole argument, as @carry does, but never ends,
  // and Idris did not prove it does.
  idr.func private @loops(%x: !idr.box<@Forest>) -> !idr.box<@Forest> {
    %r = idr.call @loops(%x) : (!idr.box<@Forest>) -> !idr.box<@Forest>
    return %r : !idr.box<@Forest>
  }
  // @carry without the proof.
  idr.func private @drift(%n: i64, %x: !idr.box<@Forest>) -> !idr.box<@Forest> {
    %r = idr.match_lit %n : i64 -> (!idr.box<@Forest>) {
    case 0 {
      idr.yield %x : !idr.box<@Forest>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %y = idr.call @drift(%m, %x) : (i64, !idr.box<@Forest>) -> !idr.box<@Forest>
      idr.yield %y : !idr.box<@Forest>
    }
    }
    return %r : !idr.box<@Forest>
  }
  idr.func private @crashes(%x: !idr.box<@Forest>) -> !idr.box<@Forest> attributes {total} {
    %r = idr.match %x : !idr.box<@Forest> -> (!idr.box<@Forest>) {
    case @Done() {
      idr.yield %x : !idr.box<@Forest>
    }
    case @More(%t: !idr.box<@Tree>, %rest: !idr.box<@Forest>) {
      idr.crash "unhandled input for crashes"
      ub.unreachable
    }
    }
    return %r : !idr.box<@Forest>
  }
  idr.func private @zero(%i: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %i : !idr.nat -> (!idr.nat) {
    case #idr.big<"0"> {
      %z = idr.constant #idr.big<"0"> : !idr.nat
      idr.yield %z : !idr.nat
    }
    default {
      %z = idr.constant #idr.big<"0"> : !idr.nat
      idr.yield %z : !idr.nat
    }
    }
    return %r : !idr.nat
  }
  idr.func private @flip(%t: !idr.box<@Term>) -> !idr.box<@Term> attributes {total} {
    %r = idr.match %t : !idr.box<@Term> -> (!idr.box<@Term>) {
    case @App(%f: !idr.box<@Term>, %a: !idr.box<@Term>) {
      %f2 = idr.call @flip(%f) : (!idr.box<@Term>) -> !idr.box<@Term>
      %a2 = idr.call @flip(%a) : (!idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@App(%a2, %f2) : (!idr.box<@Term>, !idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    default {
      idr.yield %t : !idr.box<@Term>
    }
    }
    return %r : !idr.box<@Term>
  }
  // Gives back its argument only if @flip does, on a part below it: in
  // whatever order the functions are checked, it keeps its call once @flip
  // is found not to.
  idr.func private @leans(%t: !idr.box<@Term>) -> !idr.box<@Term> attributes {total} {
    %r = idr.match %t : !idr.box<@Term> -> (!idr.box<@Term>) {
    case @App(%f: !idr.box<@Term>, %a: !idr.box<@Term>) {
      %f2 = idr.call @flip(%f) : (!idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@App(%f2, %a) : (!idr.box<@Term>, !idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    default {
      idr.yield %t : !idr.box<@Term>
    }
    }
    return %r : !idr.box<@Term>
  }
  // Two arguments of the type it gives back; it gives back the second.
  idr.func private @second(%x: !idr.box<@Forest>, %y: !idr.box<@Forest>) -> !idr.box<@Forest> attributes {total} {
    return %y : !idr.box<@Forest>
  }
  idr.func @main(%t: !idr.box<@Term>, %f: !idr.box<@Forest>, %i: !idr.nat, %d: !idr.nat, %k: i64) -> (!idr.box<@Term>, !idr.box<@Term>, !idr.box<@Forest>, !idr.nat, !idr.box<@Forest>, !idr.box<@Forest>, !idr.box<@Forest>, !idr.nat, !idr.box<@Term>, !idr.box<@Forest>, !idr.box<@Forest>, !idr.box<@Term>, !idr.box<@Forest>) {
    %t1 = idr.call @weakenTerm(%t) : (!idr.box<@Term>) -> !idr.box<@Term>
    %t2 = idr.call @weakenUnder(%d, %t1) : (!idr.nat, !idr.box<@Term>) -> !idr.box<@Term>
    %f1 = idr.call @weakenForest(%f) : (!idr.box<@Forest>) -> !idr.box<@Forest>
    %j = idr.call @weaken(%i) : (!idr.nat) -> !idr.nat
    %fl = idr.lin.enter %f : !idr.lin<!idr.box<@Forest>>
    %f2 = idr.call @same(%fl) : (!idr.lin<!idr.box<@Forest>>) -> !idr.box<@Forest>
    %f3 = idr.call @loops(%f) : (!idr.box<@Forest>) -> !idr.box<@Forest>
    %f4 = idr.call @crashes(%f) : (!idr.box<@Forest>) -> !idr.box<@Forest>
    %z = idr.call @zero(%i) : (!idr.nat) -> !idr.nat
    %s = idr.call @flip(%t) : (!idr.box<@Term>) -> !idr.box<@Term>
    %c = idr.call @carry(%k, %f) : (i64, !idr.box<@Forest>) -> !idr.box<@Forest>
    %r = idr.call @drift(%k, %f) : (i64, !idr.box<@Forest>) -> !idr.box<@Forest>
    %l = idr.call @leans(%t) : (!idr.box<@Term>) -> !idr.box<@Term>
    %g = idr.call @second(%f4, %f) : (!idr.box<@Forest>, !idr.box<@Forest>) -> !idr.box<@Forest>
    return %t1, %t2, %f1, %j, %f2, %f3, %f4, %z, %s, %c, %r, %l, %g : !idr.box<@Term>, !idr.box<@Term>, !idr.box<@Forest>, !idr.nat, !idr.box<@Forest>, !idr.box<@Forest>, !idr.box<@Forest>, !idr.nat, !idr.box<@Term>, !idr.box<@Forest>, !idr.box<@Forest>, !idr.box<@Term>, !idr.box<@Forest>
  }
}
