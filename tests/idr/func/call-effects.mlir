// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 3' %s > %t.write.mlir
// RUN: idris-mlir-opt %t.write.mlir --idr-effects | FileCheck %s --check-prefix=WRITE
// RUN: awk '/^\/\/ -----/ { n++; next } n == 4' %s > %t.canon.mlir
// RUN: idris-mlir-opt %t.canon.mlir --canonicalize | FileCheck %s --check-prefix=CANON
// NEEDS-ACCEPTANCE: the texts of the call-site effects verifier, as C02 writes them.
// What a call may do is its own `effects`, which is what MLIR asks of it:
// whether canonicalize may erase it, CSE merge it or LICM hoist it is asked
// of the op alone. It is a copy of its callee's, kept only because an op's
// effects have no symbol table, and it is exactly the callee's: no closure
// is passed to a call by the time effects are known, so a call that says
// less or more than its callee does is refused, and a callee without one
// may do everything, which no call says, since no writer stores the full
// set. idr-effects writes each call's from its callee's; a call without one
// may do anything, so canonicalize keeps it even when nothing uses it.

idr.func private @f(%w: !idr.world) -> !idr.world attributes {effects = #idr.effects<io, crash>} {
  return %w : !idr.world
}
idr.func private @g(%w: !idr.world) -> !idr.world {
  // expected-error @+1 {{carries effects #idr.effects<io>, but @f does #idr.effects<io, crash>}}
  %w1 = idr.call @f(%w) effects = <io> : (!idr.world) -> !idr.world
  return %w1 : !idr.world
}

// -----

idr.func private @f(%x: i64) -> i64 {
  return %x : i64
}
idr.func private @g(%x: i64) -> i64 {
  // expected-error @+1 {{carries effects #idr.effects<io, crash>, but @f does #idr.effects<io, crash, diverge>}}
  %r = idr.call @f(%x) effects = <io, crash> : (i64) -> i64
  return %r : i64
}

// -----

// A call that says more than its callee is refused too: it would keep a
// call that its callee lets go.
idr.func private @f(%x: i64) -> i64 attributes {total, effects = #idr.effects<crash>} {
  return %x : i64
}
idr.func private @g(%x: i64) -> i64 {
  %a = idr.call @f(%x) effects = <crash> : (i64) -> i64
  // expected-error @+1 {{carries effects #idr.effects<io, crash>, but @f does #idr.effects<crash>}}
  %b = idr.call @f(%a) effects = <io, crash> : (i64) -> i64
  return %b : i64
}

// -----

// WRITE-LABEL: idr.func private @caller(
// WRITE: call @pure(%{{[^)]*}}) effects = <none> : (i64) -> i64
// WRITE: call @partial(%{{[^)]*}}) effects = <diverge> : (i64) -> i64
// WRITE: call @say(%{{[^)]*}}) effects = <io> : (!idr.world) -> !idr.world
idr.func private @pure(%x: i64) -> i64 attributes {total} {
  %y = arith.addi %x, %x : i64
  return %y : i64
}
idr.func private @say(%w: !idr.world) -> !idr.world attributes {total} {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}
// Idris did not prove that it ends.
idr.func private @partial(%x: i64) -> i64 {
  %r = idr.call @partial(%x) : (i64) -> i64
  return %r : i64
}
idr.func private @caller(%x: i64, %w: !idr.world) -> (i64, !idr.world) {
  %a = idr.call @pure(%x) : (i64) -> i64
  %b = idr.call @partial(%a) : (i64) -> i64
  %w1 = idr.call @say(%w) : (!idr.world) -> !idr.world
  return %b, %w1 : i64, !idr.world
}

// -----

// CANON-LABEL: idr.func private @keeps(
// CANON-NEXT: call @pure(
// CANON-NEXT: return
// CANON-LABEL: idr.func private @drops(
// CANON-NOT: call
// CANON: return
idr.func private @pure(%x: i64) -> i64 attributes {total, effects = #idr.effects<none>} {
  %y = arith.addi %x, %x : i64
  return %y : i64
}
idr.func private @keeps(%x: i64) -> i64 {
  %unused = idr.call @pure(%x) : (i64) -> i64
  return %x : i64
}
idr.func private @drops(%x: i64) -> i64 {
  %unused = idr.call @pure(%x) effects = <none> : (i64) -> i64
  return %x : i64
}
