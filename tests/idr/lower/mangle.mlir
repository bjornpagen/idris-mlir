// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// A function's symbol is its Idris name with its instance's arguments,
// which may hold any character; from idr-lower on it is the name LLVM and
// the linker take, so phase 0 writes every character outside letters,
// digits, `_` and `.` as `$`, its code point, `$`: the function, its calls
// and the call a force makes of a memo label's function alike. Static data
// is named in that alphabet already and keeps its names.
// CHECK-LABEL: func.func private @Main.show$91$Prelude.Types.Nat$93$(
// CHECK-LABEL: func.func private @Main.pair$91$Prelude.Types.Nat$44$$32$Prelude.Types.Nat$93$(
// CHECK: call @Main.show$91$Prelude.Types.Nat$93$(
// CHECK-LABEL: func.func private @Main.go$39$(
// CHECK-LABEL: func.func private @Main.caf$233$(
// CHECK: call @Main.go$39$(
// CHECK-LABEL: func.func @Prog.main(
// CHECK: call @Main.pair$91$Prelude.Types.Nat$44$$32$Prelude.Types.Nat$93$(
// CHECK: call @Main.caf$233$(
!lazy$0 = !idr.data<"lazy$0", memo [@"Main.go'"(i64), @running(), @forced(i64)]>
module {
  idr.func private @"Main.show[Prelude.Types.Nat]"(%n: i64) -> i64 attributes {total} {
    %r = arith.addi %n, %n : i64
    return %r : i64
  }
  idr.func private @"Main.pair[Prelude.Types.Nat, Prelude.Types.Nat]"(%a: i64, %b: i64) -> i64 attributes {total} {
    %s = idr.call @"Main.show[Prelude.Types.Nat]"(%a) : (i64) -> i64
    %r = arith.addi %s, %b : i64
    return %r : i64
  }
  idr.func private @"Main.go'"(%x: i64) -> i64 attributes {total} {
    %one = arith.constant 1 : i64
    %r = arith.addi %x, %one : i64
    return %r : i64
  }
  idr.func private @"Main.café"(%t: !idr.box<!lazy$0>) -> i64 {
    %v = idr.force %t : !idr.box<!lazy$0> -> i64
    return %v : i64
  }
  idr.func @Prog.main() -> i64 {
    %two = arith.constant 2 : i64
    %p = idr.call @"Main.pair[Prelude.Types.Nat, Prelude.Types.Nat]"(%two, %two) : (i64, i64) -> i64
    %t = idr.con @"Main.go'"(%p) : (i64) -> !idr.box<!lazy$0>
    %v = idr.call @"Main.café"(%t) : (!idr.box<!lazy$0>) -> i64
    return %v : i64
  }
}
