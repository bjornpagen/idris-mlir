// RUN: idris-mlir-opt %s -split-input-file -o /dev/null
// RUN: %status 1 idris-mlir-opt %s -split-input-file --control-flow-sink -o /dev/null 2> %t.err
// RUN: FileCheck %s --implicit-check-not=error: < %t.err
// A field or a tag read is Pure though it loads from the cell, since a cell
// never changes while a reference to it is live. In the owned stage
// references end, and a pass that moves a read past the drop of the
// reference it reads through, as control-flow-sink does when it moves a Pure
// op into the one region that uses it, fails at the owned stage's verifier,
// which runs after every pass, instead of reading a freed cell. As written,
// each read comes before the drop.
// CHECK: error: 'idr.field' op uses a value whose last reference is gone on this path
// CHECK: error: 'idr.tag' op uses a value whose last reference is gone on this path

module attributes {idr.program} {
  idr.data @P box {
    idr.ctor @P (i64, i64)
  }
  func.func private @field(%b: i1, %p: !idr.own<!idr.box<@P>>) -> i64 {
    %v = idr.borrow %p : !idr.own<!idr.box<@P>>
    %x = idr.field %v[@P, 0] : !idr.box<@P> -> i64
    %y = idr.field %v[@P, 1] : !idr.box<@P> -> i64
    idr.drop %p : !idr.own<!idr.box<@P>>
    %r = idr.match_lit %b : i1 -> (i64) {
    case true {
      idr.yield %x : i64
    }
    default {
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

module attributes {idr.program} {
  idr.data @P box {
    idr.ctor @P (i64, i64)
  }
  func.func private @tag(%b: i1, %p: !idr.own<!idr.box<@P>>) -> i64 {
    %v = idr.borrow %p : !idr.own<!idr.box<@P>>
    %t = idr.tag %v : !idr.box<@P>
    %y = idr.field %v[@P, 1] : !idr.box<@P> -> i64
    idr.drop %p : !idr.own<!idr.box<@P>>
    %r = idr.match_lit %b : i1 -> (i64) {
    case true {
      idr.yield %t : i64
    }
    default {
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
