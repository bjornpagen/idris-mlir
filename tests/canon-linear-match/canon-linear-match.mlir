// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=matches=@of_param,matches-nothing=@of_con,\
// RUN: builds-nothing=@of_con,builds-nothing=@two_reads,reads-no-fields=@two_reads,\
// RUN: matches-nothing=@gives_back,calls=@gives_back:@keep -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=matches-nothing=@of_con,builds-nothing=@of_con,builds-nothing=@two_reads,reads-no-fields=@two_reads,matches-nothing=@gives_back' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=matches=@of_con' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=calls=@of_con:@keep' -o /dev/null
// BEFORE-DAG: expected matches-nothing: {{.*}}@of_con
// BEFORE-DAG: expected builds-nothing: {{.*}}@of_con
// BEFORE-DAG: expected builds-nothing: {{.*}}@two_reads
// BEFORE-DAG: expected reads-no-fields: {{.*}}@two_reads
// BEFORE-DAG: expected matches-nothing: {{.*}}@gives_back
// A match takes a linear value apart, as its one use. A match on a linear
// parameter stays, one region or many: there is no other reader to read
// its fields from. A match on a value that entered its grade from a
// constructor is that constructor's region, its fields the constructor's,
// held as the region held them; its default region gets the value back.
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it, and @of_con neither matches nor calls
// @keep after it.

!P = !idr.data<"P", plain [@MkP(i64, !idr.lin<i64>)]>
!P2 = !idr.data<"P2", plain [@MkP2(!idr.lin<i64>, !idr.lin<i64>)]>
!Q = !idr.data<"Q", plain [@A(i64), @B()]>
idr.program @"linear-match" root(@root) stage(first) {
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
  // The program's root runs the functions above on what it reads: the
  // byte's low two bits pick one, and the rest of it is its number.
  // @gives_back hands its default's value to @keep, which crashes.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c4 = arith.constant 4 : i64
    %sel = arith.remui %byte, %c4 : i64
    %a = arith.divui %byte, %c4 : i64
    %b = arith.addi %a, %c1 : i64
    %r = idr.match_lit %sel : i64 -> (i64) {
    case 0 {
      %l = idr.lin.enter %b : !idr.lin<i64>
      %c = idr.con !P @MkP(%a : i64, %l : !idr.lin<i64>)
      %p = idr.lin.enter %c : !idr.lin<!P>
      %v = idr.call @of_param(%p) : (!idr.lin<!P>) -> i64
      idr.yield %v : i64
    }
    case 1 {
      %l = idr.lin.enter %b : !idr.lin<i64>
      %v = idr.call @of_con(%a, %l) : (i64, !idr.lin<i64>) -> i64
      idr.yield %v : i64
    }
    case 2 {
      %l = idr.lin.enter %a : !idr.lin<i64>
      %m = idr.lin.enter %byte : !idr.lin<i64>
      %v = idr.call @two_reads(%l, %m) : (!idr.lin<i64>, !idr.lin<i64>) -> i64
      idr.yield %v : i64
    }
    default(%d: i64) {
      %v = idr.call @gives_back() : () -> i64
      idr.yield %v : i64
    }
    }
    %w1 = idr.io.put_sint %r, %w0 : i64
    return %w1 : !idr.world
  }
}
