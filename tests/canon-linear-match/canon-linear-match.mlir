// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=matches=@of_param,matches-nothing=@of_con,\
// RUN: builds-nothing=@of_con,builds-nothing=@two_reads,reads-no-fields=@two_reads,\
// RUN: matches-nothing=@gives_back,calls=@gives_back:@keep -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// A match takes a linear value apart, as its one use. A match on a linear
// parameter stays, one region or many: there is no other reader to read
// its fields from. A match on a value that entered its grade from a
// constructor is that constructor's region, its fields the constructor's,
// held as the region held them; its default region gets the value back.

!P = !idr.data<"P", plain [@MkP(i64, !idr.lin<i64>)]>
!P2 = !idr.data<"P2", plain [@MkP2(!idr.lin<i64>, !idr.lin<i64>)]>
!Q = !idr.data<"Q", plain [@A(i64), @B()]>
idr.program @"linear-match" root(@gives_back) stage(first) {
  idr.func @keep(%q: !idr.lin<!Q>) -> i64 {
    idr.crash "no body"
    ub.unreachable
  }

  idr.func @of_param(%p: !idr.lin<!P>) -> i64 {
    %r = idr.match %p : !idr.lin<!P> -> (i64) {
    case @MkP(%a: i64, %b: !idr.lin<i64>) {
      %x = idr.lin.use %b : !idr.lin<i64>
      %s = arith.addi %a, %x : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }

  idr.func @of_con(%a: i64, %b: !idr.lin<i64>) -> i64 {
    %c = idr.con !P @MkP(%a : i64, %b : !idr.lin<i64>)
    %p = idr.lin.enter %c : !idr.lin<!P>
    %r = idr.match %p : !idr.lin<!P> -> (i64) {
    case @MkP(%x: i64, %y: !idr.lin<i64>) {
      %v = idr.lin.use %y : !idr.lin<i64>
      %s = arith.addi %x, %v : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }

  // Two linear fields of one constructor, each read once: both move into
  // their reads, and the constructor goes.
  idr.func @two_reads(%a: !idr.lin<i64>, %b: !idr.lin<i64>) -> i64 {
    %c = idr.con !P2 @MkP2(%a : !idr.lin<i64>, %b : !idr.lin<i64>)
    %x = idr.field %c : !P2 @MkP2[0] -> i64
    %y = idr.field %c : !P2 @MkP2[1] -> i64
    %s = arith.addi %x, %y : i64
    return %s : i64
  }
  idr.func @gives_back() -> i64 {
    %c = idr.con !Q @B()
    %p = idr.lin.enter %c : !idr.lin<!Q>
    %r = idr.match %p : !idr.lin<!Q> -> (i64) {
    case @A(%x: i64) {
      idr.yield %x : i64
    }
    default(%q: !idr.lin<!Q>) {
      %k = idr.call @keep(%q) : (!idr.lin<!Q>) -> i64
      idr.yield %k : i64
    }
    }
    return %r : i64
  }
}
