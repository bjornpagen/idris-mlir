// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A reference lives in an SSA value or in memory, and every op that moves
// one between them declares the move. A memo cell's captures are owned
// because its force, idr.memo.run, moves them out of the cell into its
// region, and nothing else gives them: a label's field read any other way,
// by a match's case or by idr.field, is a view of the cell. So a capture
// taken over twice (the case's binding and a field read, each dropped: a
// double release) and a capture taken with no force (the cell then frees it
// again when it dies) cannot be written: each read is a view by its type.
// The rule under both: an owned value an op makes holds a reference only
// from a source the op declares (OwnedWalk::make): a use it takes over, a
// fresh value, a callee's result, what an exchange moved out, or a
// reference of its own (idr.dup). Static data its op makes from nothing a
// count reaches is no source either: at a view's grade it is a view that
// lives as long as the program, and what is read from it is a view of it,
// so the forced value of a static memo cell moved into another cell
// without a reference of its own (two holders, one reference) is refused
// as any consumed view is. The last two programs are the near neighbours
// that verify: the static value's reference taken by an idr.dup, and the
// captures moved out by the force, dropped once.

!T = !idr.data<"T", memo [@lbl(!idr.str) label @lbl, @running() running, @forced(!idr.str) forced]>
idr.program @"sources" root(@Main.main) stage(owned) {
  idr.func @twice(%t: !idr.q<many, borrow, !idr.box<!T>>) -> i64 {
    // expected-error @+1 {{has result '!idr.own<!idr.str>', but the field of a '!idr.q<many, borrow, !idr.box}}
    %s = idr.field %t : !idr.q<many, borrow, !idr.box<!T>> @lbl[0] -> !idr.own<!idr.str>
    idr.drop %s : !idr.own<!idr.str>
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}

// -----

!T = !idr.data<"T", memo [@lbl(!idr.str) label @lbl, @running() running, @forced(!idr.str) forced]>
idr.program @"sources" root(@Main.main) stage(owned) {
  idr.func @peek(%t: !idr.q<many, borrow, !idr.box<!T>>) -> i64 {
    // expected-error @+1 {{case @lbl must take the constructor's fields at the scrutinee's grade}}
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!T>> -> (i64) {
    case @lbl(%s: !idr.own<!idr.str>) {
      idr.drop %s : !idr.own<!idr.str>
      %c = arith.constant 1 : i64
      idr.yield %c : i64
    }
    case @running() {
      %c = arith.constant 2 : i64
      idr.yield %c : i64
    }
    case @forced(%v: !idr.q<many, borrow, !idr.str>) {
      %c = arith.constant 3 : i64
      idr.yield %c : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}

// -----

!T = !idr.data<"T", memo [@lbl(!idr.str) label @lbl, @running() running, @forced(!idr.str) forced]>
idr.program @"sources" root(@Main.main) stage(owned) {
  idr.func @stat(%o: !idr.q<many, borrow, !idr.box<!T>>) -> i64 {
    %t = idr.constant !idr.q<many, borrow, !idr.box<!T>> #idr.con<!T, @forced, ["abc"]>
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!T>> -> (i64) {
    case @lbl(%s: !idr.q<many, borrow, !idr.str>) {
      %c = arith.constant 0 : i64
      idr.yield %c : i64
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    // expected-note @+1 {{the value is defined here}}
    case @forced(%v: !idr.q<many, borrow, !idr.str>) {
      idr.memo.run %o : !idr.q<many, borrow, !idr.box<!T>> @lbl {
      ^bb0(%c: !idr.own<!idr.str>):
        idr.drop %c : !idr.own<!idr.str>
        // expected-error @+1 {{consumes a view, which holds no reference}}
        idr.array.yield %v : !idr.q<many, borrow, !idr.str>
      }
      %c = arith.constant 1 : i64
      idr.yield %c : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}

// -----

!T = !idr.data<"T", memo [@lbl(!idr.str) label @lbl, @running() running, @forced(!idr.str) forced]>
idr.program @"sources" root(@Main.main) stage(owned) {
  idr.func @stat(%o: !idr.q<many, borrow, !idr.box<!T>>) -> i64 {
    %t = idr.constant !idr.q<many, borrow, !idr.box<!T>> #idr.con<!T, @forced, ["abc"]>
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!T>> -> (i64) {
    case @lbl(%s: !idr.q<many, borrow, !idr.str>) {
      %c = arith.constant 0 : i64
      idr.yield %c : i64
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.q<many, borrow, !idr.str>) {
      idr.memo.run %o : !idr.q<many, borrow, !idr.box<!T>> @lbl {
      ^bb0(%c: !idr.own<!idr.str>):
        idr.drop %c : !idr.own<!idr.str>
        %d = idr.dup %v : !idr.q<many, borrow, !idr.str>
        idr.array.yield %d : !idr.own<!idr.str>
      }
      %c = arith.constant 1 : i64
      idr.yield %c : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}

// -----

!T = !idr.data<"T", memo [@lbl(!idr.str) label @lbl, @running() running, @forced(!idr.str) forced]>
idr.program @"sources" root(@Main.main) stage(owned) {
  idr.func @lbl(%s: !idr.q<many, borrow, !idr.str>) -> !idr.own<!idr.str> attributes {total} {
    %r = idr.dup %s : !idr.q<many, borrow, !idr.str>
    return %r : !idr.own<!idr.str>
  }
  idr.func @T.force(%t: !idr.q<many, borrow, !idr.box<!T>>) -> !idr.own<!idr.str> {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!T>> -> (!idr.own<!idr.str>) {
    case @lbl(%s: !idr.q<many, borrow, !idr.str>) {
      %v = idr.memo.run %t : !idr.q<many, borrow, !idr.box<!T>> @lbl -> !idr.own<!idr.str> {
      ^bb0(%c: !idr.own<!idr.str>):
        %b = idr.borrow %c : !idr.own<!idr.str>
        %x = idr.call @lbl(%b) : (!idr.q<many, borrow, !idr.str>) -> !idr.own<!idr.str>
        idr.drop %c : !idr.own<!idr.str>
        %xb = idr.borrow %x : !idr.own<!idr.str>
        %x2 = idr.dup %xb : !idr.q<many, borrow, !idr.str>
        idr.array.yield %x2, %x : !idr.own<!idr.str>, !idr.own<!idr.str>
      }
      idr.yield %v : !idr.own<!idr.str>
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.q<many, borrow, !idr.str>) {
      %d = idr.dup %v : !idr.q<many, borrow, !idr.str>
      idr.yield %d : !idr.own<!idr.str>
    }
    }
    return %r : !idr.own<!idr.str>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}
