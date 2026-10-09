// RUN: idris-mlir-opt %s --idr-lower -o /dev/null
// RUN: not idris-mlir-opt %s --idr-lower=jit=1 -o /dev/null 2>&1 | FileCheck %s
// The lowering has one mode: compile-time evaluation runs the program's
// own, and adds its meter after it (idr-meter), so idr-lower takes no
// option that would lower a module another way.
// CHECK: no such option jit
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
