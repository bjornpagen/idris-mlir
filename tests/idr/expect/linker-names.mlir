// NEEDS-ACCEPTANCE: that linker-names holds of the lowered module pulled out of the CLEAN lines and fails once, at the symbol with a `-` in it.
// RUN: sed -n 's|^// CLEAN: ||p' %s > %t.clean.mlir
// RUN: idris-mlir-opt %t.clean.mlir --idr-expect=holds=linker-names -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=linker-names -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// From idr-lower on a symbol is the name the linker takes, written in
// letters, digits, `_`, `.` and `$`, the alphabet idr-lower spells every
// other character in (the CLEAN module); a `-` itself is outside it.
// CHECK-DAG: error: expected linker-names: @Main.a-b is written outside the linker's alphabet
// CLEAN: module {
// CLEAN:   func.func @Main.a$2d$b(%x: i64) -> i64 {
// CLEAN:     return %x : i64
// CLEAN:   }
// CLEAN: }
module {
  func.func @"Main.a-b"(%x: i64) -> i64 {
    return %x : i64
  }
}
