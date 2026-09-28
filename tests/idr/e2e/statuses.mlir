// RUN: %status 2 idris-mlir-cc %s
// RUN: %status 2 idris-mlir-cc %s --check -o %t.o
// RUN: idris-mlir-cc %s --check
// RUN: not ls %t.o
// RUN: sed -n 's|^// INPUT: ||p' %s > %t.foreign.mlir
// RUN: %status 1 idris-mlir-cc %t.foreign.mlir -o %t.o 2> %t.err
// RUN: FileCheck %s --check-prefix=FOREIGN < %t.err
// RUN: not ls %t.o
// rule: DRV-CC-2, IDR-IN-1
// Usage errors are status 2: neither -o nor --check, or both. --check runs
// the pipeline through idr-check-profile and writes nothing. The program is
// parsed with exactly the contract's dialects, so an op of any other (here
// scf) fails to parse (IDR-IN-1): status 1, and no output.
// FOREIGN: error: Dialect `scf' not found for custom op 'scf.execute_region'
// INPUT: module attributes {idr.program} {
// INPUT:   func.func @Prog.main() -> i64 {
// INPUT:     %r = scf.execute_region -> i64 {
// INPUT:       %z = arith.constant 0 : i64
// INPUT:       scf.yield %z : i64
// INPUT:     }
// INPUT:     return %r : i64
// INPUT:   }
// INPUT: }
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
