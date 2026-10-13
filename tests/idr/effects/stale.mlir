// RUN: idris-mlir-opt %s --idr-expect=holds=facts-as-marked -o /dev/null
// What a call may do is the effects it carries, which may be stale:
// simplification only removes what a function reaches, so a stale
// attribute says too much, and a call without one may do anything. A call
// answers from its own effects, never from its callee's, which they
// contain. A closure that became a sum after idr-effects wrote them
// counted at the call it was given to, by its label when it was made
// there, and as anything when it was not.

idr.data @fn$0 closures {
  idr.ctor @crashes ()
  idr.ctor @square ()
}

idr.func private @square(%x: i64) -> i64 attributes {total, effects = #idr.effects<none>} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
idr.func private @unknown(%x: i64) -> i64 attributes {total} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
idr.func private @crashes(%x: i64) -> i64 attributes {total, effects = #idr.effects<crash>} {
  %r = idr.div signed %x, %x : i64
  return %r : i64
}
// Its facts are those from before its closure became a sum, when it only
// applied one.
idr.func private @run(%f: !idr.data<@fn$0>, %x: i64) -> i64 attributes {total, effects = #idr.effects<none>} {
  %r = idr.match %f : !idr.data<@fn$0> -> (i64) {
  case @crashes() {
    %c = idr.call @crashes(%x) : (i64) -> i64
    idr.yield %c : i64
  }
  case @square() {
    %s = idr.call @square(%x) : (i64) -> i64
    idr.yield %s : i64
  }
  }
  return %r : i64
}

idr.func @main(%f: !idr.data<@fn$0>, %x: i64) {
  %a = idr.call @unknown(%x) {expect.facts = ""} : (i64) -> i64
  %sc = idr.constant #idr.con<@fn$0::@crashes, []> : !idr.data<@fn$0>
  %b = idr.call @run(%sc, %x) effects = <crash> {expect.facts = "delay"} : (!idr.data<@fn$0>, i64) -> i64
  %ss = idr.con @fn$0::@square() : () -> !idr.data<@fn$0>
  %c = idr.call @run(%ss, %x) effects = <none> {expect.facts = "drop move delay"} : (!idr.data<@fn$0>, i64) -> i64
  %d = idr.call @run(%f, %x) {expect.facts = ""} : (!idr.data<@fn$0>, i64) -> i64
  return
}
