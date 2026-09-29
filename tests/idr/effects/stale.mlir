// RUN: idris-mlir-opt %s --idr-expect=holds=facts-as-marked -o /dev/null
// The facts a function carries may be stale: simplification only removes
// what a function reaches, so a stale attribute says too much, and a
// function without one may do anything. A closure that became a sum after
// the facts were found counts at the call it is given to, by its label
// when it is made there, and as anything when it is not.

idr.data @fn$0 {
  idr.ctor @crashes tag 0 () {quantities = []}
  idr.ctor @square tag 1 () {quantities = []}
}

func.func private @square(%x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @unknown(%x: i64) -> i64 attributes {idr.total} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @crashes(%x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<crash>} {
  %r = idr.div signed %x, %x : i64
  return %r : i64
}
// Its facts are those from before its closure became a sum, when it only
// applied one.
func.func private @run(%f: !idr.data<@fn$0>, %x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
  %r = idr.match %f : !idr.data<@fn$0> -> (i64) {
  case @crashes() {
    %c = func.call @crashes(%x) : (i64) -> i64
    idr.yield %c : i64
  }
  case @square() {
    %s = func.call @square(%x) : (i64) -> i64
    idr.yield %s : i64
  }
  }
  return %r : i64
}

func.func @main(%f: !idr.data<@fn$0>, %x: i64) {
  %a = func.call @unknown(%x) {expect.facts = ""} : (i64) -> i64
  %sc = idr.constant #idr.con<@fn$0::@crashes, []> : !idr.data<@fn$0>
  %b = func.call @run(%sc, %x) {expect.facts = "delay"} : (!idr.data<@fn$0>, i64) -> i64
  %ss = idr.con @fn$0::@square() : () -> !idr.data<@fn$0>
  %c = func.call @run(%ss, %x) {expect.facts = "drop move delay"} : (!idr.data<@fn$0>, i64) -> i64
  %d = func.call @run(%f, %x) {expect.facts = ""} : (!idr.data<@fn$0>, i64) -> i64
  return
}
