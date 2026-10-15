// RUN: idris-mlir-opt %s --idr-expect=holds=facts-as-marked -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --cse --idr-expect=holds=calls=@main:@pure,calls=@main:@unknown,calls=@main:@crashes -o /dev/null
// NEEDS-ACCEPTANCE: that idr.call declares every effect to upstream, so canonicalize keeps every call, and answers move and delay with its callee's effects.
// What a call may do is its callee's effects, which the callee holds once:
// the call holds none, and to upstream's interfaces it declares every
// effect a function may have, so canonicalize erases no call and CSE
// merges none, whatever its callee. The dialect's own rewrites ask the
// callee by name: a call of a function that only computes may move across
// anything, one that may crash may still be delayed, and a callee that
// holds no effects may do anything.
idr.program @"call-effects" root(@main) stage(first) {
  idr.func @pure(%x: i64) -> i64 attributes {total, effects = #idr.effects<none>} {
    return %x : i64
  }
  idr.func @unknown(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @crashes(%x: i64) -> i64 attributes {total, effects = #idr.effects<crash>} {
    return %x : i64
  }
  idr.func @main() -> i64 {
    %c = arith.constant 3 : i64
    %a = idr.call @pure(%c) {expect.facts = "move delay"} : (i64) -> i64
    %b = idr.call @unknown(%c) {expect.facts = ""} : (i64) -> i64
    %d = idr.call @crashes(%c) {expect.facts = "delay"} : (i64) -> i64
    return %c : i64
  }
}
