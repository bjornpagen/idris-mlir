// RUN: idris-mlir-opt %s --idr-effects --idr-identity --symbol-dce | FileCheck %s --implicit-check-not=@weaken --implicit-check-not=@same --implicit-check-not=@carry
// RUN: idris-mlir-opt %s --idr-effects --idr-identity --idr-expect=holds=not-called=@weaken,not-called=@weakenTerm,not-called=@weakenUnder,not-called=@weakenTree,not-called=@weakenForest,not-called=@same,not-called=@carry -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --idr-identity -o %t.once.mlir
// RUN: idris-mlir-opt %t.once.mlir --idr-identity -o %t.twice.mlir
// RUN: idris-mlir-opt %t.once.mlir -o %t.again.mlir
// RUN: cmp %t.again.mlir %t.twice.mlir
// Once the indices are erased, a function that only rebuilds its argument
// gives it back, and every call of it becomes the argument; symbol-dce then
// erases it. Fin's weaken (FS of the weakened predecessor, on naturals);
// the weakening of a term to a larger scope, which rebuilds every node and
// weakens each variable with weaken; the same with a count it carries and
// never gives back; a tree and a forest weakened by mutual recursion, a
// region Idris proved is never taken among them; a function of a linear
// argument, whose call becomes the argument's one use; and one that passes
// its argument on whole, counting down another, which Idris proved ends.
// A function that calls itself on its whole argument without that proof,
// counting down or not, is not known to return and keeps its calls, as do
// one that crashes on a path, one that gives back zero whatever it gets,
// and one that swaps a node's children. Run again on what it leaves, the
// pass changes nothing.
// CHECK-LABEL: func.func private @loops(
// CHECK-LABEL: func.func private @drift(
// CHECK-LABEL: func.func private @crashes(
// CHECK-LABEL: func.func private @zero(
// CHECK-LABEL: func.func private @flip(
// CHECK-LABEL: func.func @main(
// CHECK-SAME: %[[T:[^:]*]]: !idr.box<@Term>, %[[F:[^:]*]]: !idr.box<@Forest>, %[[I:[^:]*]]: !idr.nat, %[[D:[^:]*]]: !idr.nat, %[[K:[^:]*]]: i64)
// CHECK: %[[FL:.*]] = idr.lin.enter %[[F]]
// CHECK: %[[FU:.*]] = idr.lin.use %[[FL]]
// CHECK: %[[F3:.*]] = {{(func.)?}}call @loops(%[[F]])
// CHECK: %[[F4:.*]] = {{(func.)?}}call @crashes(%[[F]])
// CHECK: %[[Z:.*]] = {{(func.)?}}call @zero(%[[I]])
// CHECK: %[[S:.*]] = {{(func.)?}}call @flip(%[[T]])
// CHECK: %[[R:.*]] = {{(func.)?}}call @drift(%[[K]], %[[F]])
// CHECK: return %[[T]], %[[T]], %[[F]], %[[I]], %[[FU]], %[[F3]], %[[F4]], %[[Z]], %[[S]], %[[F]], %[[R]] :
module {
  idr.data @Term box {
    idr.ctor @Var (!idr.erased, !idr.nat)
    idr.ctor @App (!idr.erased, !idr.box<@Term>, !idr.box<@Term>)
    idr.ctor @Lam (!idr.erased, !idr.box<@Term>)
    idr.ctor @Lit (!idr.erased, !idr.big)
  }
  idr.data @Tree box {
    idr.ctor @Leaf (!idr.erased, !idr.nat)
    idr.ctor @Node (!idr.erased, !idr.box<@Forest>)
  }
  idr.data @Forest box {
    idr.ctor @Done (!idr.erased)
    idr.ctor @More (!idr.erased, !idr.box<@Tree>, !idr.box<@Forest>)
  }
  // weaken FZ = FZ; weaken (FS k) = FS (weaken k)
  func.func private @weaken(%n: !idr.erased, %i: !idr.nat) -> !idr.nat attributes {idr.total} {
    %r = idr.match_lit %i : !idr.nat -> (!idr.nat) {
    case #idr.big<"0"> {
      %z = idr.constant #idr.big<"0"> : !idr.nat
      idr.yield %z : !idr.nat
    }
    default {
      %k = idr.big.pred %i
      %e = idr.constant #idr.erased : !idr.erased
      %w = func.call @weaken(%e, %k) : (!idr.erased, !idr.nat) -> !idr.nat
      %one = idr.constant #idr.big<"1"> : !idr.nat
      %s = idr.big.add %w, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }
  func.func private @weakenTerm(%n: !idr.erased, %t: !idr.box<@Term>) -> !idr.box<@Term> attributes {idr.total} {
    %e = idr.constant #idr.erased : !idr.erased
    %r = idr.match %t : !idr.box<@Term> -> (!idr.box<@Term>) {
    case @Var(%m: !idr.erased, %i: !idr.nat) {
      %j = func.call @weaken(%e, %i) : (!idr.erased, !idr.nat) -> !idr.nat
      %v = idr.con @Term::@Var(%e, %j) : (!idr.erased, !idr.nat) -> !idr.box<@Term>
      idr.yield %v : !idr.box<@Term>
    }
    case @App(%m: !idr.erased, %f: !idr.box<@Term>, %a: !idr.box<@Term>) {
      %f2 = func.call @weakenTerm(%e, %f) : (!idr.erased, !idr.box<@Term>) -> !idr.box<@Term>
      %a2 = func.call @weakenTerm(%e, %a) : (!idr.erased, !idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@App(%e, %f2, %a2) : (!idr.erased, !idr.box<@Term>, !idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    case @Lam(%m: !idr.erased, %b: !idr.box<@Term>) {
      %b2 = func.call @weakenTerm(%e, %b) : (!idr.erased, !idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@Lam(%e, %b2) : (!idr.erased, !idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    case @Lit(%m: !idr.erased, %x: !idr.big) {
      %c = idr.con @Term::@Lit(%e, %x) : (!idr.erased, !idr.big) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    }
    return %r : !idr.box<@Term>
  }
  // The count goes one up under each binder, and is never given back.
  func.func private @weakenUnder(%d: !idr.nat, %n: !idr.erased, %t: !idr.box<@Term>) -> !idr.box<@Term> attributes {idr.total} {
    %e = idr.constant #idr.erased : !idr.erased
    %r = idr.match %t : !idr.box<@Term> -> (!idr.box<@Term>) {
    case @Var(%m: !idr.erased, %i: !idr.nat) {
      %j = func.call @weaken(%e, %i) : (!idr.erased, !idr.nat) -> !idr.nat
      %v = idr.con @Term::@Var(%m, %j) : (!idr.erased, !idr.nat) -> !idr.box<@Term>
      idr.yield %v : !idr.box<@Term>
    }
    case @App(%m: !idr.erased, %f: !idr.box<@Term>, %a: !idr.box<@Term>) {
      %f2 = func.call @weakenUnder(%d, %e, %f) : (!idr.nat, !idr.erased, !idr.box<@Term>) -> !idr.box<@Term>
      %a2 = func.call @weakenUnder(%d, %e, %a) : (!idr.nat, !idr.erased, !idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@App(%e, %f2, %a2) : (!idr.erased, !idr.box<@Term>, !idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    case @Lam(%m: !idr.erased, %b: !idr.box<@Term>) {
      %one = idr.constant #idr.big<"1"> : !idr.nat
      %d1 = idr.big.add %d, %one : !idr.nat
      %b2 = func.call @weakenUnder(%d1, %e, %b) : (!idr.nat, !idr.erased, !idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@Lam(%e, %b2) : (!idr.erased, !idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    case @Lit(%m: !idr.erased, %x: !idr.big) {
      idr.yield %t : !idr.box<@Term>
    }
    }
    return %r : !idr.box<@Term>
  }
  func.func private @weakenTree(%n: !idr.erased, %t: !idr.box<@Tree>) -> !idr.box<@Tree> attributes {idr.total} {
    %e = idr.constant #idr.erased : !idr.erased
    %r = idr.match %t : !idr.box<@Tree> -> (!idr.box<@Tree>) {
    case @Leaf(%m: !idr.erased, %i: !idr.nat) {
      // Idris proved a leaf's index is never zero.
      %l = idr.match_lit %i : !idr.nat -> (!idr.box<@Tree>) {
      case #idr.big<"0"> {
        ub.unreachable
      }
      default {
        %j = func.call @weaken(%e, %i) : (!idr.erased, !idr.nat) -> !idr.nat
        %v = idr.con @Tree::@Leaf(%e, %j) : (!idr.erased, !idr.nat) -> !idr.box<@Tree>
        idr.yield %v : !idr.box<@Tree>
      }
      }
      idr.yield %l : !idr.box<@Tree>
    }
    case @Node(%m: !idr.erased, %f: !idr.box<@Forest>) {
      %f2 = func.call @weakenForest(%e, %f) : (!idr.erased, !idr.box<@Forest>) -> !idr.box<@Forest>
      %v = idr.con @Tree::@Node(%e, %f2) : (!idr.erased, !idr.box<@Forest>) -> !idr.box<@Tree>
      idr.yield %v : !idr.box<@Tree>
    }
    }
    return %r : !idr.box<@Tree>
  }
  func.func private @weakenForest(%n: !idr.erased, %f: !idr.box<@Forest>) -> !idr.box<@Forest> attributes {idr.total} {
    %e = idr.constant #idr.erased : !idr.erased
    %r = idr.match %f : !idr.box<@Forest> -> (!idr.box<@Forest>) {
    case @Done(%m: !idr.erased) {
      %v = idr.con @Forest::@Done(%e) : (!idr.erased) -> !idr.box<@Forest>
      idr.yield %v : !idr.box<@Forest>
    }
    case @More(%m: !idr.erased, %t: !idr.box<@Tree>, %rest: !idr.box<@Forest>) {
      %t2 = func.call @weakenTree(%e, %t) : (!idr.erased, !idr.box<@Tree>) -> !idr.box<@Tree>
      %rest2 = func.call @weakenForest(%e, %rest) : (!idr.erased, !idr.box<@Forest>) -> !idr.box<@Forest>
      %v = idr.con @Forest::@More(%e, %t2, %rest2) : (!idr.erased, !idr.box<@Tree>, !idr.box<@Forest>) -> !idr.box<@Forest>
      idr.yield %v : !idr.box<@Forest>
    }
    }
    return %r : !idr.box<@Forest>
  }
  // A linear argument: the match takes it apart, or gives it back.
  func.func private @same(%x: !idr.lin<!idr.box<@Forest>>) -> !idr.box<@Forest> attributes {idr.total} {
    %r = idr.match %x : !idr.lin<!idr.box<@Forest>> -> (!idr.box<@Forest>) {
    case @Done(%m: !idr.erased) {
      %v = idr.con @Forest::@Done(%m) : (!idr.erased) -> !idr.box<@Forest>
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
  func.func private @carry(%n: i64, %x: !idr.box<@Forest>) -> !idr.box<@Forest> attributes {idr.total} {
    %r = idr.match_lit %n : i64 -> (!idr.box<@Forest>) {
    case 0 {
      idr.yield %x : !idr.box<@Forest>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %y = func.call @carry(%m, %x) : (i64, !idr.box<@Forest>) -> !idr.box<@Forest>
      idr.yield %y : !idr.box<@Forest>
    }
    }
    return %r : !idr.box<@Forest>
  }
  // Calls itself on its whole argument, as @carry does, but never ends,
  // and Idris did not prove it does.
  func.func private @loops(%x: !idr.box<@Forest>) -> !idr.box<@Forest> {
    %r = func.call @loops(%x) : (!idr.box<@Forest>) -> !idr.box<@Forest>
    return %r : !idr.box<@Forest>
  }
  // @carry without the proof.
  func.func private @drift(%n: i64, %x: !idr.box<@Forest>) -> !idr.box<@Forest> {
    %r = idr.match_lit %n : i64 -> (!idr.box<@Forest>) {
    case 0 {
      idr.yield %x : !idr.box<@Forest>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %y = func.call @drift(%m, %x) : (i64, !idr.box<@Forest>) -> !idr.box<@Forest>
      idr.yield %y : !idr.box<@Forest>
    }
    }
    return %r : !idr.box<@Forest>
  }
  func.func private @crashes(%x: !idr.box<@Forest>) -> !idr.box<@Forest> attributes {idr.total} {
    %r = idr.match %x : !idr.box<@Forest> -> (!idr.box<@Forest>) {
    case @Done(%m: !idr.erased) {
      idr.yield %x : !idr.box<@Forest>
    }
    case @More(%m: !idr.erased, %t: !idr.box<@Tree>, %rest: !idr.box<@Forest>) {
      idr.crash "unhandled input for crashes"
      ub.unreachable
    }
    }
    return %r : !idr.box<@Forest>
  }
  func.func private @zero(%i: !idr.nat) -> !idr.nat attributes {idr.total} {
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
  func.func private @flip(%t: !idr.box<@Term>) -> !idr.box<@Term> attributes {idr.total} {
    %e = idr.constant #idr.erased : !idr.erased
    %r = idr.match %t : !idr.box<@Term> -> (!idr.box<@Term>) {
    case @App(%m: !idr.erased, %f: !idr.box<@Term>, %a: !idr.box<@Term>) {
      %f2 = func.call @flip(%f) : (!idr.box<@Term>) -> !idr.box<@Term>
      %a2 = func.call @flip(%a) : (!idr.box<@Term>) -> !idr.box<@Term>
      %c = idr.con @Term::@App(%e, %a2, %f2) : (!idr.erased, !idr.box<@Term>, !idr.box<@Term>) -> !idr.box<@Term>
      idr.yield %c : !idr.box<@Term>
    }
    default {
      idr.yield %t : !idr.box<@Term>
    }
    }
    return %r : !idr.box<@Term>
  }
  func.func @main(%t: !idr.box<@Term>, %f: !idr.box<@Forest>, %i: !idr.nat, %d: !idr.nat, %k: i64) -> (!idr.box<@Term>, !idr.box<@Term>, !idr.box<@Forest>, !idr.nat, !idr.box<@Forest>, !idr.box<@Forest>, !idr.box<@Forest>, !idr.nat, !idr.box<@Term>, !idr.box<@Forest>, !idr.box<@Forest>) {
    %e = idr.constant #idr.erased : !idr.erased
    %t1 = func.call @weakenTerm(%e, %t) : (!idr.erased, !idr.box<@Term>) -> !idr.box<@Term>
    %t2 = func.call @weakenUnder(%d, %e, %t1) : (!idr.nat, !idr.erased, !idr.box<@Term>) -> !idr.box<@Term>
    %f1 = func.call @weakenForest(%e, %f) : (!idr.erased, !idr.box<@Forest>) -> !idr.box<@Forest>
    %j = func.call @weaken(%e, %i) : (!idr.erased, !idr.nat) -> !idr.nat
    %fl = idr.lin.enter %f : !idr.lin<!idr.box<@Forest>>
    %f2 = func.call @same(%fl) : (!idr.lin<!idr.box<@Forest>>) -> !idr.box<@Forest>
    %f3 = func.call @loops(%f) : (!idr.box<@Forest>) -> !idr.box<@Forest>
    %f4 = func.call @crashes(%f) : (!idr.box<@Forest>) -> !idr.box<@Forest>
    %z = func.call @zero(%i) : (!idr.nat) -> !idr.nat
    %s = func.call @flip(%t) : (!idr.box<@Term>) -> !idr.box<@Term>
    %c = func.call @carry(%k, %f) : (i64, !idr.box<@Forest>) -> !idr.box<@Forest>
    %r = func.call @drift(%k, %f) : (i64, !idr.box<@Forest>) -> !idr.box<@Forest>
    return %t1, %t2, %f1, %j, %f2, %f3, %f4, %z, %s, %c, %r : !idr.box<@Term>, !idr.box<@Term>, !idr.box<@Forest>, !idr.nat, !idr.box<@Forest>, !idr.box<@Forest>, !idr.box<@Forest>, !idr.nat, !idr.box<@Term>, !idr.box<@Forest>, !idr.box<@Forest>
  }
}
