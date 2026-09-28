// RUN: %status 1 idris-mlir-opt %s --split-input-file --idr-check-profile -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// rule: PROF-DATA-3, PROF-HEAP-1, PROF-HEAP-2, PROF-HEAP-3, PROF-HEAP-4, PROF-PRIM-4, PROF-TYPE-4, DIAG-ONE-1
// Each module holds one kind of allocation at runtime. The check reports
// the first violation in op order, with its rule, and fails.

// A box built from a runtime value.
// CHECK: Main.idr:3:7: error: unsupported (PROF-DATA-3): recursive data built at runtime: Cons has a field that is not known at compile time
// CHECK-NOT: error:
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.box<@L>) {quantities = ["w", "w"]}
  }
  func.func private @one(%n: i64 {idr.quantity = "w"}) -> !idr.box<@L> {
    %nil = idr.constant #idr.con<@L::@Nil, []> : !idr.box<@L>
    %l = idr.con @L::@Cons(%n, %nil) : (i64, !idr.box<@L>) -> !idr.box<@L> loc("Main.idr":3:7)
    return %l : !idr.box<@L>
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// A closure of an argument that captures a runtime value.
// CHECK: Main.idr:4:9: error: unsupported (PROF-HEAP-1): function value built at runtime: a closure of @add that no finite choice of functions stands for
// CHECK-NOT: error:
module attributes {idr.program} {
  func.func private @add(%a: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  func.func private @adder(%n: i64 {idr.quantity = "w"}) -> !idr.fn<(i64) -> (i64)> {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":4:9)
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// A suspension (Lazy) that captures a runtime value.
// CHECK: Main.idr:5:2: error: unsupported (PROF-HEAP-2): Lazy value built at runtime: a suspension of @sq whose captures are not known at compile time
// CHECK-NOT: error:
module attributes {idr.program} {
  func.func private @sq(%a: i64 {idr.quantity = "w"}) -> i64 {
    %y = arith.muli %a, %a : i64
    return %y : i64
  }
  func.func private @delay(%n: i64 {idr.quantity = "w"}) -> !idr.fn<() -> (i64)> {
    %f = idr.closure @sq(%n) : (i64) -> !idr.fn<() -> (i64)> loc("Main.idr":5:2)
    return %f : !idr.fn<() -> (i64)>
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// A closure that grows while the specialization of its callee stopped.
// CHECK: Main.idr:8:3: error: unsupported (PROF-HEAP-4): function value grows: a closure of @twice is built in or passed to @iter, whose specialization stopped
// CHECK-NOT: error:
module attributes {idr.program} {
  func.func private @twice(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %z : i64
  }
  func.func private @iter(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %n: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.spec_stopped} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = idr.closure @twice(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":8:3)
      %y = func.call @iter(%g, %m, %x) {idr.spec_stopped} : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// A string built at runtime and passed to a function instead of output.
// CHECK: Main.idr:9:9: error: unsupported (PROF-HEAP-3): string built at runtime: the result of idr.str.cons is passed to func.call instead of being written by output
// CHECK-NOT: error:
module attributes {idr.program} {
  func.func private @greet(%s: !idr.str {idr.quantity = "w"}, %w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %w1 = idr.io.put_str %s, %w
    %w2 = func.call @greet(%s, %w1) : (!idr.str, !idr.world) -> !idr.world
    return %w2 : !idr.world
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %bang = idr.constant "!" : !idr.str
    %s = idr.str.cons %c, %bang loc("Main.idr":9:9)
    %w2 = func.call @greet(%s, %w1) : (!idr.str, !idr.world) -> !idr.world
    return %w2 : !idr.world
  }
}

// -----

// A string built at runtime reaching a primitive other than output: the
// error is at the primitive.
// CHECK: Main.idr:12:4: error: unsupported (PROF-PRIM-4): idr.match_lit of a string built at runtime by idr.str.from_char
// CHECK-NOT: error:
module attributes {idr.program} {
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %s = idr.str.from_char %c loc("Main.idr":11:4)
    %r = idr.match_lit %s : !idr.str -> (i32) {
    case "y" {
      %one = arith.constant 1 : i32
      idr.yield %one : i32
    }
    default {
      %zero = arith.constant 0 : i32
      idr.yield %zero : i32
    }
    } loc("Main.idr":12:4)
    %w2 = idr.io.put_char %r, %w1
    return %w2 : !idr.world
  }
}

// -----

// An Integer computed at runtime.
// CHECK: Main.idr:13:1: error: unsupported (PROF-TYPE-4): Integer computed at runtime by idr.big.from_int, which may allocate
// CHECK-NOT: error:
module attributes {idr.program} {
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %b = idr.big.from_int signed %n : i64 loc("Main.idr":13:1)
    %one = idr.constant #idr.big<"1"> : !idr.big
    %s = idr.big.add %b, %one loc("Main.idr":13:2)
    %t = idr.big.to_int %s : i64
    %w2 = idr.io.put_int signed %t, %w1 : i64
    return %w2 : !idr.world
  }
}
