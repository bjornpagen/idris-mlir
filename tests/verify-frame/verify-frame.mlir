// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// The rules of the frame, on types (IR/Lifetimes.h): a cell of the frame
// (idr.cell.stack) gives a box of the frame, `, frame` in its grade, and
// what reaches one is of the frame too. Such a value is never returned,
// never moved into memory that exists before the op that moves it (here a
// memo cell's forced state, which the caller's memo cell keeps after the
// frame is gone: the leak of a static lazy list and the crash of one forced
// twice), never filled into a cell of the heap, never forwarded out of a
// region that runs again, and never passed to a self call that becomes the
// next iteration of a loop. Where memory's slot has a type, the type
// already refuses it: a memo cell's forced state is of the heap. Each refusal has its near neighbour last, the
// same program with the cell on the heap or the value of the frame kept in
// it, which verifies.

!P = !idr.data<"P">
!U = !idr.data<"U">
#types = #idr.types<
  "P" = plain [@MkP(!idr.str)],
  "U" = memo [@mk(!idr.str) label @mk, @running() running, @forced(!idr.box<!P>) forced]
>
idr.program @"frame" root(@Main.main) stage(owned) types #types {
  idr.func @U.force(%t: !idr.q<many, borrow, !idr.box<!U>>) -> !idr.own<!idr.box<!P>> {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!U>> -> (!idr.own<!idr.box<!P>>) {
    case @mk(%s: !idr.q<many, borrow, !idr.str>) {
      idr.memo.run %t : !idr.q<many, borrow, !idr.box<!U>> @mk {
      ^bb0(%c: !idr.own<!idr.str>):
        %k = idr.cell.stack : !idr.cell<!idr.box<!P>, @MkP, frame>
        %f = idr.cell.init %k : !idr.cell<!idr.box<!P>, @MkP, frame> (%c : !idr.own<!idr.str>)
        // expected-error @+1 {{at 0 where idr.memo.run takes}}
        idr.array.yield %f : !idr.q<many, own, !idr.box<!P>, frame>
      }
      idr.crash "the value moved into the cell"
      ub.unreachable
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.q<many, borrow, !idr.box<!P>>) {
      %d = idr.dup %v : !idr.q<many, borrow, !idr.box<!P>>
      idr.yield %d : !idr.own<!idr.box<!P>>
    }
    }
    return %r : !idr.own<!idr.box<!P>>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}

// -----

!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@MkP(!idr.str)]
>
idr.program @"frame" root(@Main.main) stage(owned) types #types {
  // expected-error @+1 {{returns a value of the frame}}
  idr.func @ret(%s: !idr.own<!idr.str>) -> !idr.q<many, own, !idr.box<!P>, frame> {
    %k = idr.cell.stack : !idr.cell<!idr.box<!P>, @MkP, frame>
    %b = idr.cell.init %k : !idr.cell<!idr.box<!P>, @MkP, frame> (%s : !idr.own<!idr.str>)
    return %b : !idr.q<many, own, !idr.box<!P>, frame>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}

// -----

!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@MkP(!idr.str)]
>
idr.program @"frame" root(@Main.main) stage(owned) types #types {
  idr.func @ret(%s: !idr.own<!idr.str>) -> !idr.own<!idr.box<!P>> {
    %k = idr.cell.stack : !idr.cell<!idr.box<!P>, @MkP, frame>
    %b = idr.cell.init %k : !idr.cell<!idr.box<!P>, @MkP, frame> (%s : !idr.own<!idr.str>)
    // expected-error @+1 {{as result 0, but @ret returns}}
    return %b : !idr.q<many, own, !idr.box<!P>, frame>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}

// -----

!P = !idr.data<"P">
!Q = !idr.data<"Q">
#types = #idr.types<
  "P" = plain [@MkP(!idr.str)],
  "Q" = plain [@MkQ(!idr.box<!P>)]
>
idr.program @"frame" root(@Main.main) stage(owned) types #types {
  idr.func @fill(%s: !idr.own<!idr.str>) -> !idr.own<!idr.box<!Q>> {
    %k = idr.cell.stack : !idr.cell<!idr.box<!P>, @MkP, frame>
    %p = idr.cell.init %k : !idr.cell<!idr.box<!P>, @MkP, frame> (%s : !idr.own<!idr.str>)
    %h = idr.cell.new : !idr.cell<!idr.box<!Q>, @MkQ>
    // expected-error @+1 {{its fields are its cell's constructor's}}
    %q = idr.cell.init %h : !idr.cell<!idr.box<!Q>, @MkQ> (%p : !idr.q<many, own, !idr.box<!P>, frame>)
    return %q : !idr.own<!idr.box<!Q>>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}

// -----

!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@MkP(!idr.str)]
>
idr.program @"frame" root(@Main.main) stage(owned) types #types {
  // expected-note @+1 {{the value of the frame is defined here}}
  idr.func @spin(%n: i64, %s: !idr.q<many, own, !idr.box<!P>, frame>) -> i64 {
    %z = arith.constant 0 : i64
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.drop %s : !idr.q<many, own, !idr.box<!P>, frame>
      idr.yield %z : i64
    }
    default(%m: i64) {
      %one = arith.constant 1 : i64
      %next = arith.subi %m, %one : i64
      // expected-error @+1 {{takes a value of the frame and passes it to a self call that becomes the next iteration of a loop in the frame}}
      %x = idr.call @spin(%next, %s) : (i64, !idr.q<many, own, !idr.box<!P>, frame>) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}

// -----

// The near neighbours, each of which verifies: the cell on the heap moved
// into the memo cell; the box of the frame read and dropped where it was
// made; a field of the frame filled into a cell of the frame; and a value
// of the frame passed to a call that is not in tail position.
!P = !idr.data<"P">
!Q = !idr.data<"Q">
!U = !idr.data<"U">
#types = #idr.types<
  "P" = plain [@MkP(!idr.str)],
  "Q" = plain [@MkQ(!idr.box<!P>)],
  "U" = memo [@mk(!idr.str) label @mk, @running() running, @forced(!idr.box<!P>) forced]
>
idr.program @"frame" root(@Main.main) stage(owned) types #types {
  idr.func @U.force(%t: !idr.q<many, borrow, !idr.box<!U>>) -> !idr.own<!idr.box<!P>> {
    %r = idr.match %t : !idr.q<many, borrow, !idr.box<!U>> -> (!idr.own<!idr.box<!P>>) {
    case @mk(%s: !idr.q<many, borrow, !idr.str>) {
      %v = idr.memo.run %t : !idr.q<many, borrow, !idr.box<!U>> @mk -> !idr.own<!idr.box<!P>> {
      ^bb0(%c: !idr.own<!idr.str>):
        %k = idr.cell.new : !idr.cell<!idr.box<!P>, @MkP>
        %f = idr.cell.init %k : !idr.cell<!idr.box<!P>, @MkP> (%c : !idr.own<!idr.str>)
        %fb = idr.borrow %f : !idr.own<!idr.box<!P>>
        %g = idr.dup %fb : !idr.q<many, borrow, !idr.box<!P>>
        idr.array.yield %g, %f : !idr.own<!idr.box<!P>>, !idr.own<!idr.box<!P>>
      }
      idr.yield %v : !idr.own<!idr.box<!P>>
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.q<many, borrow, !idr.box<!P>>) {
      %d = idr.dup %v : !idr.q<many, borrow, !idr.box<!P>>
      idr.yield %d : !idr.own<!idr.box<!P>>
    }
    }
    return %r : !idr.own<!idr.box<!P>>
  }
  idr.func @read(%s: !idr.own<!idr.str>) -> i64 {
    %k = idr.cell.stack : !idr.cell<!idr.box<!P>, @MkP, frame>
    %p = idr.cell.init %k : !idr.cell<!idr.box<!P>, @MkP, frame> (%s : !idr.own<!idr.str>)
    %h = idr.cell.stack : !idr.cell<!idr.box<!Q>, @MkQ, frame>
    %q = idr.cell.init %h : !idr.cell<!idr.box<!Q>, @MkQ, frame> (%p : !idr.q<many, own, !idr.box<!P>, frame>)
    %v = idr.borrow %q : !idr.q<many, own, !idr.box<!Q>, frame>
    %n = idr.call @size(%v) : (!idr.q<many, borrow, !idr.box<!Q>, frame>) -> i64
    idr.drop %q : !idr.q<many, own, !idr.box<!Q>, frame>
    return %n : i64
  }
  idr.func @size(%q: !idr.q<many, borrow, !idr.box<!Q>, frame>) -> i64 {
    %p = idr.field %q : !idr.q<many, borrow, !idr.box<!Q>, frame> @MkQ[0] -> !idr.q<many, borrow, !idr.box<!P>, frame>
    %s = idr.field %p : !idr.q<many, borrow, !idr.box<!P>, frame> @MkP[0] -> !idr.q<many, borrow, !idr.str>
    %n = idr.str.length borrow %s
    return %n : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    return %w : !idr.world
  }
}
