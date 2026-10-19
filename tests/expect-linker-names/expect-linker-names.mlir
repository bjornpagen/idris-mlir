// RUN: idris-mlir-opt %s --idr-expect=holds=linker-names -verify-diagnostics -o /dev/null
// RUN: sed '/^  func.func @"/,/^  }/d' %s > %t.kept.mlir
// RUN: idris-mlir-opt %t.kept.mlir --idr-expect=holds=linker-names -o /dev/null
// From idr-lower on a symbol is the name the linker takes, written in
// letters, digits, `_`, `.` and `$`, the alphabet idr-lower spells every
// other character in (@Main.a$2d$b, @Prog.go_on_2, which raise no error);
// a `-`, a space, or a letter outside ASCII, is outside it, each one
// error. The module without those (the sed drops each function whose name
// needs quotes) holds.
module {
  func.func @Main.a$2d$b(%x: i64) -> i64 {
    return %x : i64
  }
  func.func @Prog.go_on_2(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error @below {{expected linker-names: }}
  func.func @"Main.a-b"(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error @below {{expected linker-names: }}
  func.func @"Main.a b"(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error @below {{expected linker-names: }}
  func.func @"Main.caf\C3\A9"(%x: i64) -> i64 {
    return %x : i64
  }
}
