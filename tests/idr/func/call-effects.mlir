// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 3' %s > %t.write.mlir
// RUN: idris-mlir-opt %t.write.mlir --idr-effects | FileCheck %s --check-prefix=WRITE
// RUN: awk '/^\/\/ -----/ { n++; next } n == 4' %s > %t.canon.mlir
// RUN: idris-mlir-opt %t.canon.mlir --canonicalize | FileCheck %s --check-prefix=CANON
// What a call may do is its own `effects`, which is what MLIR asks of it:
// whether canonicalize may erase it, CSE merge it or LICM hoist it is asked
// of the op alone. The callee's `effects` is the authority: a call that
// says less than its callee may do is refused, and a callee without one may
// do everything, which no call says, since no writer stores the full set.
// idr-effects writes the call's from its callee's; a call without one may
// do anything, so canonicalize keeps it even when nothing uses it.

idr.func private @f(%w: !idr.world) -> !idr.world attributes {effects = #idr.effects<io, crash>} {
  return %w : !idr.world
}
idr.func private @g(%w: !idr.world) -> !idr.world {
  // expected-error @+1 {{carries effects #idr.effects<io>, but @f may do #idr.effects<io, crash>}}
  %w1 = idr.call @f(%w) {effects = #idr.effects<io>} : (!idr.world) -> !idr.world
  return %w1 : !idr.world
}

// -----

idr.func private @f(%x: i64) -> i64 {
  return %x : i64
}
idr.func private @g(%x: i64) -> i64 {
  // expected-error @+1 {{carries effects #idr.effects<io, crash>, but @f may do #idr.effects<io, crash, diverge>}}
  %r = idr.call @f(%x) {effects = #idr.effects<io, crash>} : (i64) -> i64
  return %r : i64
}

// -----

// A call may say more than its callee: what a closure it is given may do
// counts at the call too.
idr.func private @f(%x: i64) -> i64 attributes {total, effects = #idr.effects<crash>} {
  return %x : i64
}
idr.func private @g(%x: i64) -> i64 {
  %a = idr.call @f(%x) {effects = #idr.effects<crash>} : (i64) -> i64
  %b = idr.call @f(%a) {effects = #idr.effects<io, crash>} : (i64) -> i64
  return %b : i64
}

// -----

// WRITE-LABEL: idr.func @caller(
// WRITE: call @pure(%{{[^)]*}}) {effects = #idr.effects<none>} : (i64) -> i64
// WRITE: call @unknown(%{{[^)]*}}) : (i64) -> i64
// WRITE: call @say(%{{[^)]*}}) {effects = #idr.effects<io>} : (!idr.world) -> !idr.world
idr.func private @pure(%x: i64) -> i64 attributes {total} {
  %y = arith.addi %x, %x : i64
  return %y : i64
}
idr.func private @say(%w: !idr.world) -> !idr.world attributes {total} {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}
idr.func private @unknown(%x: i64) -> i64
idr.func @caller(%x: i64, %w: !idr.world) -> (i64, !idr.world) {
  %a = idr.call @pure(%x) : (i64) -> i64
  %b = idr.call @unknown(%a) : (i64) -> i64
  %w1 = idr.call @say(%w) : (!idr.world) -> !idr.world
  return %b, %w1 : i64, !idr.world
}

// -----

// CANON-LABEL: idr.func @keeps(
// CANON-NEXT: call @pure(
// CANON-NEXT: return
// CANON-LABEL: idr.func @drops(
// CANON-NOT: call
// CANON: return
idr.func private @pure(%x: i64) -> i64 attributes {total, effects = #idr.effects<none>} {
  %y = arith.addi %x, %x : i64
  return %y : i64
}
idr.func @keeps(%x: i64) -> i64 {
  %unused = idr.call @pure(%x) : (i64) -> i64
  return %x : i64
}
idr.func @drops(%x: i64) -> i64 {
  %unused = idr.call @pure(%x) {effects = #idr.effects<none>} : (i64) -> i64
  return %x : i64
}
