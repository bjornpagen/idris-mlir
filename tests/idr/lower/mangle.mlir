// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=linker-names,lowered -o /dev/null
// RUN: FileCheck %s < %t.mlir
// A function's symbol is its Idris name with its instance's arguments,
// which may hold any character; from idr-lower on it is the name LLVM and
// the linker take, so phase 0 writes every character outside letters,
// digits, `_` and `.` as `$`, its code point, `$`: the function and its
// calls alike, so every symbol the program defines is in that alphabet.
// Static data is named in it already and keeps its names. The encoding is
// the names the linker sees, so it is checked as written.
// CHECK-LABEL: func.func private @Main.show$91$Prelude.Types.Nat$93$(
// CHECK-LABEL: func.func private @Main.pair$91$Prelude.Types.Nat$44$$32$Prelude.Types.Nat$93$(
// CHECK: call @Main.show$91$Prelude.Types.Nat$93$(
// CHECK-LABEL: func.func private @Main.go$39$(
// CHECK-LABEL: func.func private @Main.caf$233$(
// CHECK: call @Main.go$39$(
// CHECK-LABEL: func.func @Prog.main(
// CHECK: call @Main.pair$91$Prelude.Types.Nat$44$$32$Prelude.Types.Nat$93$(
// CHECK: call @Main.caf$233$(
idr.program @mangle root(@Prog.main) stage(owned) {
  idr.func @"Main.show[Prelude.Types.Nat]"(%n: i64) -> i64 attributes {total} {
    %r = arith.addi %n, %n : i64
    return %r : i64
  }
  idr.func @"Main.pair[Prelude.Types.Nat, Prelude.Types.Nat]"(%a: i64, %b: i64) -> i64 attributes {total} {
    %s = idr.call @"Main.show[Prelude.Types.Nat]"(%a) : (i64) -> i64
    %r = arith.addi %s, %b : i64
    return %r : i64
  }
  idr.func @"Main.go'"(%x: i64) -> i64 attributes {total} {
    %one = arith.constant 1 : i64
    %r = arith.addi %x, %one : i64
    return %r : i64
  }
  idr.func @"Main.café"(%x: i64) -> i64 {
    %v = idr.call @"Main.go'"(%x) : (i64) -> i64
    return %v : i64
  }
  idr.func @Prog.main() -> i64 {
    %two = arith.constant 2 : i64
    %p = idr.call @"Main.pair[Prelude.Types.Nat, Prelude.Types.Nat]"(%two, %two) : (i64, i64) -> i64
    %v = idr.call @"Main.café"(%p) : (i64) -> i64
    return %v : i64
  }
}
