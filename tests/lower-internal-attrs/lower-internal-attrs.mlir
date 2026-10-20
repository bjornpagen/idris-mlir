// RUN: idris-mlir-opt %s --idr-target --idr-lower --idr-entry --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-llvm,lowered,calls=@g:@f -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// The facts of an idr.func (what Idris proved, total; what the frontend
// decided, instance and no_inline): idr-lower reads what LLVM needs from
// them and keeps none, so what LLVM gets carries nothing of the idr
// dialect, and no attribute under the name of one of those facts. And
// LLVM takes it as it is: the module, given the build's target, goes to
// LLVM as idris-mlir sends a module of the LLVM dialect alone, and its
// program exits as the program as written does, with the 3 the reference
// at the end (REF) returns (%differential, on the one input, none, since
// it reads none).
// STDIN:
idr.program @"internal-attrs" root(@Main.main) stage(owned) types #idr.types<> {
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
// The reference:
// REF: idr.program @ref root(@Main.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Main.main() -> i64 {
// REF:     %c = arith.constant 3 : i64
// REF:     return %c : i64
// REF:   }
// REF: }
