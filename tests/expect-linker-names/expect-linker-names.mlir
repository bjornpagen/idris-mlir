// RUN: idris-mlir-opt %s --idr-expect=holds=linker-names -verify-diagnostics -o /dev/null
// From idr-lower on a symbol is the name the linker takes, written in
// letters, digits, `_`, `.` and `$`, the alphabet idr-lower spells every
// other character in (@Main.a$2d$b, which raises no error); a `-` itself is
// outside it.
module {
  func.func @Main.a$2d$b(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error @below {{expected linker-names: }}
  func.func @"Main.a-b"(%x: i64) -> i64 {
    return %x : i64
  }
}
