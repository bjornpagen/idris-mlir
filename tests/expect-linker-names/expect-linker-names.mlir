// RUN: idris-mlir-opt %s --idr-expect=holds=linker-names -verify-diagnostics -o /dev/null
// RUN: sed -e '/^  func.func private @"/,/^  }/d' -e '/^  func.func private @Main\./,/^  }/d' %s > %t.kept.mlir
// RUN: idris-mlir-opt %t.kept.mlir --idr-expect=holds=linker-names -o /dev/null
// From the lowering on a symbol is the name the linker takes. Every
// function the program defines (each private: the process entry is the
// module's one public function) carries the program's prefix, `idr.`, so
// none is a runtime symbol or the C entry, and is written in letters,
// digits, `_`, `.` and `$`, the alphabet the lowering spells every other
// character in (@idr.Main.a$2d$b, @idr.Prog.go_on_2, which raise no
// error); a `-`, a space, or a letter outside ASCII is outside it, and a
// name without the prefix is no program symbol, each one error. The
// module without those (the sed drops each) holds.
module {
  func.func private @idr.Main.a$2d$b(%x: i64) -> i64 {
    return %x : i64
  }
  func.func private @idr.Prog.go_on_2(%x: i64) -> i64 {
    return %x : i64
  }
  func.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    return %argc : i32
  }
  // expected-error @below {{expected linker-names: }}
  func.func private @Main.unprefixed(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error @below {{expected linker-names: }}
  func.func private @"idr.Main.a-b"(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error @below {{expected linker-names: }}
  func.func private @"idr.Main.a b"(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error @below {{expected linker-names: }}
  func.func private @"idr.Main.caf\C3\A9"(%x: i64) -> i64 {
    return %x : i64
  }
}
