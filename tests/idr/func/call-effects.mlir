// RUN: idris-mlir-opt %s --idr-expect=holds=facts-as-marked -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=never-calls=@main:@pure,calls=@main:@unknown,calls=@main:@crashes -o /dev/null
// NEEDS-ACCEPTANCE: idr.call's MemoryEffectOpInterface reports its callee's effects (R02, effectsOf).
// What a call may do is its callee's effects, which the callee holds once:
// the call carries no copy, and asks its callee through the program's
// symbol table when MLIR asks it, so whether canonicalize may erase it,
// CSE merge it or LICM hoist it is its callee's to say. A callee that holds
// none may do anything, so canonicalize keeps a call of it even when
// nothing uses it, as it keeps a call of one that may crash.
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
    %a = idr.call @pure(%c) {expect.facts = "drop move delay merge"} : (i64) -> i64
    %b = idr.call @unknown(%c) {expect.facts = ""} : (i64) -> i64
    %d = idr.call @crashes(%c) {expect.facts = "delay"} : (i64) -> i64
    return %c : i64
  }
}
