// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: mlir-opt %t.mlir --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts \
// RUN:   | mlir-translate --mlir-to-llvmir -o %t.ll
// RUN: %cc -Wno-override-module %t.ll -o %t
// RUN: %status 14 %t
// A loop whose scf.condition forwards one scf.if result twice, the shape of
// upstream/while-move-if-down-duplicates: it runs once, both after-region
// arguments are 7, and the program exits with 14. Upstream's WhileMoveIfDown
// would give the second argument the else value and the program 7; with the
// idr dialect loaded, canonicalize first has the after region read the value
// through the first argument only.
module attributes {idr.program} {
  func.func @main() -> i64 {
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %c7 = arith.constant 7 : i64
    %r:2 = scf.while (%i = %c0) : (i64) -> (i64, i64) {
      %go = arith.cmpi slt, %i, %c1 : i64
      %v = scf.if %go -> i64 {
        scf.yield %c7 : i64
      } else {
        scf.yield %i : i64
      }
      scf.condition(%go) %v, %v : i64, i64
    } do {
    ^bb0(%a: i64, %b: i64):
      %s = arith.addi %a, %b : i64
      scf.yield %s : i64
    }
    return %r#0 : i64
  }
}
