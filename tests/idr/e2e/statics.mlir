// RUN: idris-mlir-cc %s -o %t.o --timing 2> %t.timing
// RUN: FileCheck %s --check-prefix=TIMING < %t.timing
// RUN: %cc %t.o -o %t
// RUN: %t | FileCheck %s
// rule: LOW-CONST-1, LOW-BOX-1, LOW-STR-2, EVAL-1, DRV-CC-2
// A list built at compile time (range is total) is static data: cells with
// count 0 in the executable, which a function that is not total (so not
// evaluated) walks at runtime, printing the strings they hold. --timing
// reports each pass and the LLVM stage.
// CHECK: 5:five 4:four 3:three 2:two 1:one 
// TIMING: Execution time report
// TIMING-DAG: IdrEval
// TIMING-DAG: IdrLower
// TIMING-DAG: LLVM
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @Cons tag 1 (i64, !idr.str, !idr.box<@List>) {quantities = ["w", "w", "w"]}
  }
  func.func private @name(%n: i64) -> !idr.str attributes {idr.total} {
    %r = idr.match_lit %n : i64 -> (!idr.str) {
    case 1 {
      %s = idr.constant "one" : !idr.str
      idr.yield %s : !idr.str
    }
    case 2 {
      %s = idr.constant "two" : !idr.str
      idr.yield %s : !idr.str
    }
    case 3 {
      %s = idr.constant "three" : !idr.str
      idr.yield %s : !idr.str
    }
    case 4 {
      %s = idr.constant "four" : !idr.str
      idr.yield %s : !idr.str
    }
    default {
      %s = idr.constant "five" : !idr.str
      idr.yield %s : !idr.str
    }
    }
    return %r : !idr.str
  }
  func.func private @range(%n: i64) -> !idr.box<@List> attributes {idr.total, no_inline} {
    %r = idr.match_lit %n : i64 -> (!idr.box<@List>) {
    case 0 {
      %nil = idr.con @List::@Nil() : () -> !idr.box<@List>
      idr.yield %nil : !idr.box<@List>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %rest = func.call @range(%m) : (i64) -> !idr.box<@List>
      %s = func.call @name(%n) : (i64) -> !idr.str
      %c = idr.con @List::@Cons(%n, %s, %rest) : (i64, !idr.str, !idr.box<@List>) -> !idr.box<@List>
      idr.yield %c : !idr.box<@List>
    }
    }
    return %r : !idr.box<@List>
  }
  func.func private @walk(%l: !idr.box<@List>, %w: !idr.world) -> !idr.world attributes {no_inline} {
    %r = idr.match %l : !idr.box<@List> -> (!idr.world) {
    case @Cons(%n: i64, %s: !idr.str, %t: !idr.box<@List>) {
      %w1 = idr.io.put_int signed %n, %w : i64
      %colon = arith.constant 58 : i32
      %w2 = idr.io.put_char %colon, %w1
      %w3 = idr.io.put_str %s, %w2
      %sp = arith.constant 32 : i32
      %w4 = idr.io.put_char %sp, %w3
      %w5 = func.call @walk(%t, %w4) : (!idr.box<@List>, !idr.world) -> !idr.world
      idr.yield %w5 : !idr.world
    }
    default {
      idr.yield %w : !idr.world
    }
    }
    return %r : !idr.world
  }
  func.func @Prog.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %five = arith.constant 5 : i64
    %l = func.call @range(%five) : (i64) -> !idr.box<@List>
    %w1 = func.call @walk(%l, %w) : (!idr.box<@List>, !idr.world) -> !idr.world
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_char %nl, %w1
    return %w2 : !idr.world
  }
}
