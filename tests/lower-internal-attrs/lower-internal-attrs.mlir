// RUN: idris-mlir-opt %s --idr-lower --idr-entry --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts --idr-expect=holds=in-llvm,lowered,calls=@g:@f -o /dev/null
// The facts of an idr.func (what Idris proved, total; what the frontend
// decided, instance and no_inline): idr-lower reads what LLVM needs from
// them and keeps none, so what LLVM gets carries nothing of the idr
// dialect, and no attribute under the name of one of those facts.
idr.program @"internal-attrs" root(@Main.main) stage(owned) {
  idr.func @f(%a: i64) -> i64 attributes {total, no_inline, instance = #idr.instance<"Main.f", []>} {
    return %a : i64
  }
  idr.func @g(%x: i64) -> i64 attributes {total} {
    %r = idr.call @f(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 3 : i64
    %r = idr.call @g(%c) : (i64) -> i64
    return %r : i64
  }
}
