// RUN: idris-mlir-opt %s --idr-isolate | FileCheck %s --check-prefix=ISOLATE --implicit-check-not=@evaluated.delay
// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s --check-prefix=CANON
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// Every Delay is an idr.delay. One whose body yields a value that exists
// above it is evaluated: forcing it computes nothing, so idr-isolate leaves
// it where it is, and the force of it is the value. A body that only builds
// a cell from values above, of constants and constructors, becomes one:
// canonicalize builds the cell before the delay, which then yields it.
// A body that computes is code, which idr-isolate outlines.

idr.data @P {
  idr.ctor @MkP (i64, i64)
}

// ISOLATE-LABEL: idr.func @evaluated(
// ISOLATE-SAME: %[[X:[^:]*]]: i64)
// ISOLATE-NEXT: %[[T:.*]] = delay : !idr.lazy<i64> {
// ISOLATE-NEXT: idr.yield %[[X]] : i64
// ISOLATE-NEXT: }
// ISOLATE-NEXT: return %[[T]]
idr.func @evaluated(%x: i64) -> !idr.lazy<i64> {
  %t = idr.delay : !idr.lazy<i64> {
    idr.yield %x : i64
  }
  return %t : !idr.lazy<i64>
}

// ISOLATE-LABEL: idr.func @computed(
// ISOLATE: suspend @computed.delay{{[0-9]+}}(
// A body that computes stays a body.
// CANON-LABEL: idr.func @computed(
// CANON: delay
// CANON-NEXT: arith.muli
idr.func @computed(%x: i64) -> !idr.lazy<i64> {
  %t = idr.delay : !idr.lazy<i64> {
    %y = arith.muli %x, %x : i64
    idr.yield %y : i64
  }
  return %t : !idr.lazy<i64>
}

// CANON-LABEL: idr.func @forced(
// CANON-SAME: %[[X:[^:]*]]: i64)
// CANON-NEXT: return %[[X]] : i64
idr.func @forced(%x: i64) -> i64 {
  %t = idr.delay : !idr.lazy<i64> {
    idr.yield %x : i64
  }
  %v = idr.force %t : !idr.lazy<i64> -> i64
  return %v : i64
}

// CANON-LABEL: idr.func @built(
// CANON-SAME: %[[X:[^:]*]]: i64, %[[Y:[^:]*]]: i64)
// CANON-NEXT: %[[P:.*]] = {{(idr\.)?}}con @P::@MkP(%[[X]], %[[Y]])
// CANON-NEXT: %[[T:.*]] = {{(idr\.)?}}delay : !idr.lazy<!P> {
// CANON-NEXT: idr.yield %[[P]] : !P
// CANON-NEXT: }
// CANON-NEXT: return %[[T]]
idr.func @built(%x: i64, %y: i64) -> !idr.lazy<!idr.data<@P>> {
  %t = idr.delay : !idr.lazy<!idr.data<@P>> {
    %p = idr.con @P::@MkP(%x, %y) : (i64, i64) -> !idr.data<@P>
    idr.yield %p : !idr.data<@P>
  }
  return %t : !idr.lazy<!idr.data<@P>>
}
