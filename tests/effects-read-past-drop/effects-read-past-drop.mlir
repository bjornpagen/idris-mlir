// RUN: idris-mlir-opt %s -split-input-file -o /dev/null
// RUN: %status 1 idris-mlir-opt %s -split-input-file --control-flow-sink -o /dev/null 2> %t.err
// RUN: FileCheck %s --implicit-check-not=error: < %t.err
// A field or a tag read is Pure though it loads from the cell, since a cell
// never changes while a reference to it is live. In the owned stage
// references end, and a pass that moves a read past the drop of the
// reference it reads through, as control-flow-sink does when it moves a Pure
// op into the one region that uses it, fails at the owned stage's verifier,
// which runs after every pass, instead of reading a freed cell. As written,
// each read comes before the drop. Which op of the sunk chain the verifier
// names is the sink's choice, so each split is checked for the error alone.
// A read that both regions use has no one region to move into, so the
// third split, where both use it, stays before its drop: no error, and the
// two errors are the first two splits'.
// CHECK-COUNT-2: error: '{{idr\.[a-z_]+}}' op uses a value whose last reference is gone on this path

!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@P(i64, i64)]
>
idr.program @"read-past-drop" root(@Prog.main) stage(owned) types #types {
  idr.func @field(%b: i1, %p: !idr.own<!idr.box<!P>>) -> i64 {
    %v = idr.borrow %p : !idr.own<!idr.box<!P>>
    %x = idr.field %v : !idr.q<many, borrow, !idr.box<!P>> @P[0] -> i64
    %y = idr.field %v : !idr.q<many, borrow, !idr.box<!P>> @P[1] -> i64
    idr.drop %p : !idr.own<!idr.box<!P>>
    %r = idr.match_lit %b : i1 -> (i64) {
    case true {
      idr.yield %x : i64
    }
    default(%d: i1) {
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@P(i64, i64)]
>
idr.program @"read-past-drop" root(@Prog.main) stage(owned) types #types {
  idr.func @tag(%b: i1, %p: !idr.own<!idr.box<!P>>) -> i64 {
    %v = idr.borrow %p : !idr.own<!idr.box<!P>>
    %t = idr.tag %v : !idr.q<many, borrow, !idr.box<!P>>
    idr.drop %p : !idr.own<!idr.box<!P>>
    %r = idr.match_lit %b : i1 -> (i64) {
    case true {
      idr.yield %t : i64
    }
    default(%d: i1) {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@P(i64, i64)]
>
idr.program @"read-past-drop" root(@Prog.main) stage(owned) types #types {
  idr.func @both(%b: i1, %p: !idr.own<!idr.box<!P>>) -> i64 {
    %v = idr.borrow %p : !idr.own<!idr.box<!P>>
    %x = idr.field %v : !idr.q<many, borrow, !idr.box<!P>> @P[0] -> i64
    idr.drop %p : !idr.own<!idr.box<!P>>
    %r = idr.match_lit %b : i1 -> (i64) {
    case true {
      idr.yield %x : i64
    }
    default(%d: i1) {
      %s = arith.addi %x, %x : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
