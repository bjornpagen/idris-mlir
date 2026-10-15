// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@weaken,not-called=@weakenTerm,not-called=@weakenUnder,not-called=@weakenTree,not-called=@weakenForest,not-called=@carry,not-called=@same,not-called=@second -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@loops -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@drift -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@flip -o /dev/null
// NEEDS-ACCEPTANCE: that idr-identity, the first step of each function's cleanup, rewrites the calls of each recursive function that gives back its argument, as the identities are solved per component.
// A function that only rebuilds its argument gives it back, and every call
// of it becomes the argument. The optimizer finds this per component of
// the call graph, callee first, and its cleanup of each caller replaces
// the calls. Fin's weaken (FS of the weakened predecessor, on naturals);
// the weakening of a term to a larger scope, which rebuilds every node and
// weakens each variable with weaken; the same with a count it carries and
// never gives back; a tree and a forest weakened by mutual recursion, a
// region Idris proved is never taken among them; a function of a linear
// argument, whose call becomes the argument's one use; one that passes its
// argument on whole, counting down another, which Idris proved ends; and
// one of two arguments of the type it gives back, whose calls become that
// argument and not the other. None of them is called afterwards. A
// function that calls itself on its whole argument without that proof,
// counting down or not, is not known to return and keeps its calls, as
// does one that swaps a node's children, which calls itself on the
// children.
!Term = !idr.data<"Term", plain [@Var(!idr.nat), @App(!idr.box<!idr.data<"Term">>, !idr.box<!idr.data<"Term">>), @Lam(!idr.box<!idr.data<"Term">>), @Lit(!idr.big)]>
!Tree = !idr.data<"Tree", plain [@Leaf(!idr.nat), @Node(!idr.box<!idr.data<"Forest", plain [@Done(), @More(!idr.box<!idr.data<"Tree">>, !idr.box<!idr.data<"Forest">>)]>>)]>
!Forest = !idr.data<"Forest", plain [@Done(), @More(!idr.box<!idr.data<"Tree", plain [@Leaf(!idr.nat), @Node(!idr.box<!idr.data<"Forest">>)]>>, !idr.box<!idr.data<"Forest">>)]>
idr.program @identity root(@root) stage(first) {
  // weaken FZ = FZ; weaken (FS k) = FS (weaken k)
  idr.func @weaken(%i: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %i : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      %z = idr.constant #idr.big<0> : !idr.nat
      idr.yield %z : !idr.nat
    }
    default {
      %k = idr.big.pred %i
      %w = idr.call @weaken(%k) : (!idr.nat) -> !idr.nat
      %one = idr.constant #idr.big<1> : !idr.nat
      %s = idr.big.add %w, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }
  idr.func @weakenTerm(%t: !idr.box<!Term>) -> !idr.box<!Term> attributes {total} {
    %r = idr.match %t : !idr.box<!Term> -> (!idr.box<!Term>) {
    case @Var(%i: !idr.nat) {
      %j = idr.call @weaken(%i) : (!idr.nat) -> !idr.nat
      %v = idr.con !idr.box<!Term> @Var(%j : !idr.nat)
      idr.yield %v : !idr.box<!Term>
    }
    case @App(%f: !idr.box<!Term>, %a: !idr.box<!Term>) {
      %f2 = idr.call @weakenTerm(%f) : (!idr.box<!Term>) -> !idr.box<!Term>
      %a2 = idr.call @weakenTerm(%a) : (!idr.box<!Term>) -> !idr.box<!Term>
      %c = idr.con !idr.box<!Term> @App(%f2 : !idr.box<!Term>, %a2 : !idr.box<!Term>)
      idr.yield %c : !idr.box<!Term>
    }
    case @Lam(%b: !idr.box<!Term>) {
      %b2 = idr.call @weakenTerm(%b) : (!idr.box<!Term>) -> !idr.box<!Term>
      %c = idr.con !idr.box<!Term> @Lam(%b2 : !idr.box<!Term>)
      idr.yield %c : !idr.box<!Term>
    }
    case @Lit(%x: !idr.big) {
      %c = idr.con !idr.box<!Term> @Lit(%x : !idr.big)
      idr.yield %c : !idr.box<!Term>
    }
    }
    return %r : !idr.box<!Term>
  }
  // The count goes one up under each binder, and is never given back.
  idr.func @weakenUnder(%d: !idr.nat, %t: !idr.box<!Term>) -> !idr.box<!Term> attributes {total} {
    %r = idr.match %t : !idr.box<!Term> -> (!idr.box<!Term>) {
    case @Var(%i: !idr.nat) {
      %j = idr.call @weaken(%i) : (!idr.nat) -> !idr.nat
      %v = idr.con !idr.box<!Term> @Var(%j : !idr.nat)
      idr.yield %v : !idr.box<!Term>
    }
    case @App(%f: !idr.box<!Term>, %a: !idr.box<!Term>) {
      %f2 = idr.call @weakenUnder(%d, %f) : (!idr.nat, !idr.box<!Term>) -> !idr.box<!Term>
      %a2 = idr.call @weakenUnder(%d, %a) : (!idr.nat, !idr.box<!Term>) -> !idr.box<!Term>
      %c = idr.con !idr.box<!Term> @App(%f2 : !idr.box<!Term>, %a2 : !idr.box<!Term>)
      idr.yield %c : !idr.box<!Term>
    }
    case @Lam(%b: !idr.box<!Term>) {
      %one = idr.constant #idr.big<1> : !idr.nat
      %d1 = idr.big.add %d, %one : !idr.nat
      %b2 = idr.call @weakenUnder(%d1, %b) : (!idr.nat, !idr.box<!Term>) -> !idr.box<!Term>
      %c = idr.con !idr.box<!Term> @Lam(%b2 : !idr.box<!Term>)
      idr.yield %c : !idr.box<!Term>
    }
    case @Lit(%x: !idr.big) {
      idr.yield %t : !idr.box<!Term>
    }
    }
    return %r : !idr.box<!Term>
  }
  idr.func @weakenTree(%t: !idr.box<!Tree>) -> !idr.box<!Tree> attributes {total} {
    %r = idr.match %t : !idr.box<!Tree> -> (!idr.box<!Tree>) {
    case @Leaf(%i: !idr.nat) {
      // Idris proved a leaf's index is never zero.
      %l = idr.match_lit %i : !idr.nat -> (!idr.box<!Tree>) {
      case #idr.big<0> {
        ub.unreachable
      }
      default {
        %j = idr.call @weaken(%i) : (!idr.nat) -> !idr.nat
        %v = idr.con !idr.box<!Tree> @Leaf(%j : !idr.nat)
        idr.yield %v : !idr.box<!Tree>
      }
      }
      idr.yield %l : !idr.box<!Tree>
    }
    case @Node(%f: !idr.box<!Forest>) {
      %f2 = idr.call @weakenForest(%f) : (!idr.box<!Forest>) -> !idr.box<!Forest>
      %v = idr.con !idr.box<!Tree> @Node(%f2 : !idr.box<!Forest>)
      idr.yield %v : !idr.box<!Tree>
    }
    }
    return %r : !idr.box<!Tree>
  }
  idr.func @weakenForest(%f: !idr.box<!Forest>) -> !idr.box<!Forest> attributes {total} {
    %r = idr.match %f : !idr.box<!Forest> -> (!idr.box<!Forest>) {
    case @Done() {
      %v = idr.con !idr.box<!Forest> @Done()
      idr.yield %v : !idr.box<!Forest>
    }
    case @More(%t: !idr.box<!Tree>, %rest: !idr.box<!Forest>) {
      %t2 = idr.call @weakenTree(%t) : (!idr.box<!Tree>) -> !idr.box<!Tree>
      %rest2 = idr.call @weakenForest(%rest) : (!idr.box<!Forest>) -> !idr.box<!Forest>
      %v = idr.con !idr.box<!Forest> @More(%t2 : !idr.box<!Tree>, %rest2 : !idr.box<!Forest>)
      idr.yield %v : !idr.box<!Forest>
    }
    }
    return %r : !idr.box<!Forest>
  }
  // A linear argument: the match takes it apart, or gives it back.
  idr.func @same(%x: !idr.lin<!idr.box<!Forest>>) -> !idr.box<!Forest> attributes {total} {
    %r = idr.match %x : !idr.lin<!idr.box<!Forest>> -> (!idr.box<!Forest>) {
    case @Done() {
      %v = idr.con !idr.box<!Forest> @Done()
      idr.yield %v : !idr.box<!Forest>
    }
    default(%back: !idr.lin<!idr.box<!Forest>>) {
      %v = idr.lin.use %back : !idr.lin<!idr.box<!Forest>>
      idr.yield %v : !idr.box<!Forest>
    }
    }
    return %r : !idr.box<!Forest>
  }
  // Counts n down, passing x on whole each time; Idris proved it ends.
  idr.func @carry(%n: i64, %x: !idr.box<!Forest>) -> !idr.box<!Forest> attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.box<!Forest>) {
    case 0 {
      idr.yield %x : !idr.box<!Forest>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %y = idr.call @carry(%m, %x) : (i64, !idr.box<!Forest>) -> !idr.box<!Forest>
      idr.yield %y : !idr.box<!Forest>
    }
    }
    return %r : !idr.box<!Forest>
  }
  // Calls itself on its whole argument, as @carry does, but never ends,
  // and Idris did not prove it does.
  idr.func @loops(%x: !idr.box<!Forest>) -> !idr.box<!Forest> {
    %r = idr.call @loops(%x) : (!idr.box<!Forest>) -> !idr.box<!Forest>
    return %r : !idr.box<!Forest>
  }
  // @carry without the proof.
  idr.func @drift(%n: i64, %x: !idr.box<!Forest>) -> !idr.box<!Forest> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!Forest>) {
    case 0 {
      idr.yield %x : !idr.box<!Forest>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %y = idr.call @drift(%m, %x) : (i64, !idr.box<!Forest>) -> !idr.box<!Forest>
      idr.yield %y : !idr.box<!Forest>
    }
    }
    return %r : !idr.box<!Forest>
  }
  idr.func @crashes(%x: !idr.box<!Forest>) -> !idr.box<!Forest> attributes {total} {
    %r = idr.match %x : !idr.box<!Forest> -> (!idr.box<!Forest>) {
    case @Done() {
      idr.yield %x : !idr.box<!Forest>
    }
    case @More(%t: !idr.box<!Tree>, %rest: !idr.box<!Forest>) {
      idr.crash "unhandled input for crashes"
      ub.unreachable
    }
    }
    return %r : !idr.box<!Forest>
  }
  idr.func @zero(%i: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %i : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      %z = idr.constant #idr.big<0> : !idr.nat
      idr.yield %z : !idr.nat
    }
    default {
      %z = idr.constant #idr.big<0> : !idr.nat
      idr.yield %z : !idr.nat
    }
    }
    return %r : !idr.nat
  }
  idr.func @flip(%t: !idr.box<!Term>) -> !idr.box<!Term> attributes {total} {
    %r = idr.match %t : !idr.box<!Term> -> (!idr.box<!Term>) {
    case @App(%f: !idr.box<!Term>, %a: !idr.box<!Term>) {
      %f2 = idr.call @flip(%f) : (!idr.box<!Term>) -> !idr.box<!Term>
      %a2 = idr.call @flip(%a) : (!idr.box<!Term>) -> !idr.box<!Term>
      %c = idr.con !idr.box<!Term> @App(%a2 : !idr.box<!Term>, %f2 : !idr.box<!Term>)
      idr.yield %c : !idr.box<!Term>
    }
    default {
      idr.yield %t : !idr.box<!Term>
    }
    }
    return %r : !idr.box<!Term>
  }
  // Gives back its argument only if @flip does, on a part below it: in
  // whatever order the functions are checked, it keeps its call once @flip
  // is found not to.
  idr.func @leans(%t: !idr.box<!Term>) -> !idr.box<!Term> attributes {total} {
    %r = idr.match %t : !idr.box<!Term> -> (!idr.box<!Term>) {
    case @App(%f: !idr.box<!Term>, %a: !idr.box<!Term>) {
      %f2 = idr.call @flip(%f) : (!idr.box<!Term>) -> !idr.box<!Term>
      %c = idr.con !idr.box<!Term> @App(%f2 : !idr.box<!Term>, %a : !idr.box<!Term>)
      idr.yield %c : !idr.box<!Term>
    }
    default {
      idr.yield %t : !idr.box<!Term>
    }
    }
    return %r : !idr.box<!Term>
  }
  // Two arguments of the type it gives back; it gives back the second.
  idr.func @second(%x: !idr.box<!Forest>, %y: !idr.box<!Forest>) -> !idr.box<!Forest> attributes {total} {
    return %y : !idr.box<!Forest>
  }
  idr.func @main(%t: !idr.box<!Term>, %f: !idr.box<!Forest>, %i: !idr.nat, %d: !idr.nat, %k: i64) -> (!idr.box<!Term>, !idr.box<!Term>, !idr.box<!Forest>, !idr.nat, !idr.box<!Forest>, !idr.box<!Forest>, !idr.box<!Forest>, !idr.nat, !idr.box<!Term>, !idr.box<!Forest>, !idr.box<!Forest>, !idr.box<!Term>, !idr.box<!Forest>) {
    %t1 = idr.call @weakenTerm(%t) : (!idr.box<!Term>) -> !idr.box<!Term>
    %t2 = idr.call @weakenUnder(%d, %t1) : (!idr.nat, !idr.box<!Term>) -> !idr.box<!Term>
    %f1 = idr.call @weakenForest(%f) : (!idr.box<!Forest>) -> !idr.box<!Forest>
    %j = idr.call @weaken(%i) : (!idr.nat) -> !idr.nat
    %fl = idr.lin.enter %f : !idr.lin<!idr.box<!Forest>>
    %f2 = idr.call @same(%fl) : (!idr.lin<!idr.box<!Forest>>) -> !idr.box<!Forest>
    %f3 = idr.call @loops(%f) : (!idr.box<!Forest>) -> !idr.box<!Forest>
    %f4 = idr.call @crashes(%f) : (!idr.box<!Forest>) -> !idr.box<!Forest>
    %z = idr.call @zero(%i) : (!idr.nat) -> !idr.nat
    %s = idr.call @flip(%t) : (!idr.box<!Term>) -> !idr.box<!Term>
    %c = idr.call @carry(%k, %f) : (i64, !idr.box<!Forest>) -> !idr.box<!Forest>
    %r = idr.call @drift(%k, %f) : (i64, !idr.box<!Forest>) -> !idr.box<!Forest>
    %l = idr.call @leans(%t) : (!idr.box<!Term>) -> !idr.box<!Term>
    %g = idr.call @second(%f4, %f) : (!idr.box<!Forest>, !idr.box<!Forest>) -> !idr.box<!Forest>
    return %t1, %t2, %f1, %j, %f2, %f3, %f4, %z, %s, %c, %r, %l, %g : !idr.box<!Term>, !idr.box<!Term>, !idr.box<!Forest>, !idr.nat, !idr.box<!Forest>, !idr.box<!Forest>, !idr.box<!Forest>, !idr.nat, !idr.box<!Term>, !idr.box<!Forest>, !idr.box<!Forest>, !idr.box<!Term>, !idr.box<!Forest>
  }
  // Values known only at run time: loops, which nothing inlines.
  idr.func @term(%k: i64) -> !idr.box<!Term> {
    %r = idr.match_lit %k : i64 -> (!idr.box<!Term>) {
    case 0 {
      %z = idr.constant #idr.big<0> : !idr.nat
      %v = idr.con !idr.box<!Term> @Var(%z : !idr.nat)
      idr.yield %v : !idr.box<!Term>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %a = idr.call @term(%m) : (i64) -> !idr.box<!Term>
      %v = idr.con !idr.box<!Term> @Lam(%a : !idr.box<!Term>)
      idr.yield %v : !idr.box<!Term>
    }
    }
    return %r : !idr.box<!Term>
  }
  idr.func @forest(%k: i64) -> !idr.box<!Forest> {
    %r = idr.match_lit %k : i64 -> (!idr.box<!Forest>) {
    case 0 {
      %v = idr.con !idr.box<!Forest> @Done()
      idr.yield %v : !idr.box<!Forest>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %z = idr.constant #idr.big<0> : !idr.nat
      %l = idr.con !idr.box<!Tree> @Leaf(%z : !idr.nat)
      %rest = idr.call @forest(%m) : (i64) -> !idr.box<!Forest>
      %v = idr.con !idr.box<!Forest> @More(%l : !idr.box<!Tree>, %rest : !idr.box<!Forest>)
      idr.yield %v : !idr.box<!Forest>
    }
    }
    return %r : !idr.box<!Forest>
  }
  idr.func @root(%w: !idr.world) -> (!idr.world, !idr.box<!Term>, !idr.box<!Term>, !idr.box<!Forest>, !idr.nat, !idr.box<!Forest>, !idr.box<!Forest>, !idr.box<!Forest>, !idr.nat, !idr.box<!Term>, !idr.box<!Forest>, !idr.box<!Forest>, !idr.box<!Term>, !idr.box<!Forest>) {
    %c, %w1 = idr.io.get_byte %w
    %k = arith.extui %c : i32 to i64
    %t = idr.call @term(%k) : (i64) -> !idr.box<!Term>
    %f = idr.call @forest(%k) : (i64) -> !idr.box<!Forest>
    %i = idr.constant #idr.big<2> : !idr.nat
    %d = idr.constant #idr.big<1> : !idr.nat
    %r:13 = idr.call @main(%t, %f, %i, %d, %k) : (!idr.box<!Term>, !idr.box<!Forest>, !idr.nat, !idr.nat, i64) -> (!idr.box<!Term>, !idr.box<!Term>, !idr.box<!Forest>, !idr.nat, !idr.box<!Forest>, !idr.box<!Forest>, !idr.box<!Forest>, !idr.nat, !idr.box<!Term>, !idr.box<!Forest>, !idr.box<!Forest>, !idr.box<!Term>, !idr.box<!Forest>)
    return %w1, %r#0, %r#1, %r#2, %r#3, %r#4, %r#5, %r#6, %r#7, %r#8, %r#9, %r#10, %r#11, %r#12 : !idr.world, !idr.box<!Term>, !idr.box<!Term>, !idr.box<!Forest>, !idr.nat, !idr.box<!Forest>, !idr.box<!Forest>, !idr.box<!Forest>, !idr.nat, !idr.box<!Term>, !idr.box<!Forest>, !idr.box<!Forest>, !idr.box<!Term>, !idr.box<!Forest>
  }
}
