// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=output-fused -o /dev/null
// A string built only to be written is written piece by piece, in the
// same order, through the world.

// "n = " ++ show n ++ "\n": three writes.
// CHECK-LABEL: func.func @append(
// CHECK-SAME: %[[N:.*]]: i64, %[[W:.*]]: !idr.world)
// CHECK-DAG: %[[A:.*]] = idr.constant "n = " : !idr.str
// CHECK-DAG: %[[NL:.*]] = idr.constant "\0A" : !idr.str
// CHECK: %[[W1:.*]] = idr.io.put_str %[[A]], %[[W]]
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_int signed %[[N]], %[[W1]] : i64
// CHECK-NEXT: %[[W3:.*]] = idr.io.put_str %[[NL]], %[[W2]]
// CHECK-NEXT: return %[[W3]]
func.func @append(%n: i64, %w: !idr.world) -> !idr.world {
  %a = idr.constant "n = " : !idr.str
  %nl = idr.constant "\n" : !idr.str
  %s = idr.str.show signed %n : i64
  %t = idr.str.append %s, %nl
  %u = idr.str.append %a, %t
  %w1 = idr.io.put_str %u, %w
  return %w1 : !idr.world
}

// CHECK-LABEL: func.func @cons(
// CHECK-SAME: %[[C:.*]]: i32, %[[S:.*]]: !idr.str, %[[W:.*]]: !idr.world)
// CHECK-NEXT: %[[W1:.*]] = idr.io.put_char %[[C]], %[[W]]
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_str %[[S]], %[[W1]]
// CHECK-NEXT: return %[[W2]]
func.func @cons(%c: i32, %s: !idr.str, %w: !idr.world) -> !idr.world {
  %t = idr.str.cons %c, %s
  %w1 = idr.io.put_str %t, %w
  return %w1 : !idr.world
}

// CHECK-LABEL: func.func @from_char(
// CHECK-SAME: %[[C:.*]]: i32, %[[W:.*]]: !idr.world)
// CHECK-NEXT: %[[W1:.*]] = idr.io.put_char %[[C]], %[[W]]
// CHECK-NEXT: return %[[W1]]
func.func @from_char(%c: i32, %w: !idr.world) -> !idr.world {
  %t = idr.str.from_char %c
  %w1 = idr.io.put_str %t, %w
  return %w1 : !idr.world
}

// CHECK-LABEL: func.func @shows(
// CHECK-SAME: %[[B:.*]]: i8, %[[D:.*]]: f64, %[[W:.*]]: !idr.world)
// CHECK-NEXT: %[[W1:.*]] = idr.io.put_int %[[B]], %[[W]] : i8
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_double %[[D]], %[[W1]]
// CHECK-NEXT: return %[[W2]]
func.func @shows(%b: i8, %d: f64, %w: !idr.world) -> !idr.world {
  %s = idr.str.show unsigned %b : i8
  %w1 = idr.io.put_str %s, %w
  %t = idr.str.show %d : f64
  %w2 = idr.io.put_str %t, %w1
  return %w2 : !idr.world
}

// A string with another use is still written piece by piece; it stays for
// that use.
// CHECK-LABEL: func.func @shared(
// CHECK: %[[S:.*]] = idr.str.from_char
// CHECK: idr.io.put_char
// CHECK: return %{{.*}}, %[[S]]
func.func @shared(%c: i32, %w: !idr.world) -> (!idr.world, !idr.str) {
  %s = idr.str.from_char %c
  %w1 = idr.io.put_str %s, %w
  return %w1, %s : !idr.world, !idr.str
}

idr.data @Chars box {
  idr.ctor @Nil ()
  idr.ctor @Cons (i32, !idr.box<@Chars>)
}
idr.data @Strs box {
  idr.ctor @Nil ()
  idr.ctor @Cons (!idr.str, !idr.box<@Strs>)
}

// putStr (pack cs) and putStr (concat ss): each list is written as it is
// walked, and no string is built.
// CHECK-LABEL: func.func @lists(
// CHECK-SAME: %[[CS:.*]]: !idr.box<@Chars>, %[[SS:.*]]: !idr.box<@Strs>, %[[W:.*]]: !idr.world)
// CHECK-NEXT: %[[W1:.*]] = idr.io.put_list %[[CS]], %[[W]] : !idr.box<@Chars>
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_list %[[SS]], %[[W1]] : !idr.box<@Strs>
// CHECK-NEXT: return %[[W2]]
func.func @lists(%cs: !idr.box<@Chars>, %ss: !idr.box<@Strs>, %w: !idr.world) -> !idr.world {
  %s = idr.str.pack %cs : !idr.box<@Chars> -> !idr.str
  %w1 = idr.io.put_str %s, %w
  %t = idr.str.concat %ss : !idr.box<@Strs> -> !idr.str
  %w2 = idr.io.put_str %t, %w1
  return %w2 : !idr.world
}

// putStrLn (pack cs): the line's characters, then its end.
// CHECK-LABEL: func.func @line(
// CHECK-SAME: %[[CS:.*]]: !idr.box<@Chars>, %[[W:.*]]: !idr.world)
// CHECK: %[[W1:.*]] = idr.io.put_list %[[CS]], %[[W]] : !idr.box<@Chars>
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_str %{{.*}}, %[[W1]]
// CHECK-NEXT: return %[[W2]]
func.func @line(%cs: !idr.box<@Chars>, %w: !idr.world) -> !idr.world {
  %nl = idr.constant "\n" : !idr.str
  %s = idr.str.pack %cs : !idr.box<@Chars> -> !idr.str
  %l = idr.str.append %s, %nl
  %w1 = idr.io.put_str %l, %w
  return %w1 : !idr.world
}

// A packed string with another use is built anyway, and written as it is.
// CHECK-LABEL: func.func @packed_and_kept(
// CHECK: %[[S:.*]] = idr.str.pack
// CHECK-NEXT: idr.io.put_str %[[S]]
// CHECK: return %{{.*}}, %[[S]]
func.func @packed_and_kept(%cs: !idr.box<@Chars>, %w: !idr.world) -> (!idr.world, !idr.str) {
  %s = idr.str.pack %cs : !idr.box<@Chars> -> !idr.str
  %w1 = idr.io.put_str %s, %w
  return %w1, %s : !idr.world, !idr.str
}

// A list that is a constant is written as the string it packs to, which is
// what writing its pack wrote: compile-time evaluation can make the list a
// constant after the output of its pack became a walk.
// CHECK-LABEL: func.func @constant_list(
// CHECK-SAME: %[[W:.*]]: !idr.world)
// CHECK-NEXT: %[[S:.*]] = idr.constant "hi" : !idr.str
// CHECK-NEXT: %[[W1:.*]] = idr.io.put_str %[[S]], %[[W]]
// CHECK-NEXT: return %[[W1]]
func.func @constant_list(%w: !idr.world) -> !idr.world {
  %cs = idr.constant #idr.con<@Chars::@Cons, [104 : i32, #idr.con<@Chars::@Cons, [105 : i32, #idr.con<@Chars::@Nil, []>]>]> : !idr.box<@Chars>
  %w1 = idr.io.put_list %cs, %w : !idr.box<@Chars>
  return %w1 : !idr.world
}

// Writing the nil writes nothing.
// CHECK-LABEL: func.func @nil(
// CHECK-SAME: %[[W:.*]]: !idr.world)
// CHECK-NEXT: return %[[W]]
func.func @nil(%w: !idr.world) -> !idr.world {
  %ss = idr.con @Strs::@Nil() : () -> !idr.box<@Strs>
  %w1 = idr.io.put_list %ss, %w : !idr.box<@Strs>
  return %w1 : !idr.world
}

// Writing a cell writes its element, then the rest, and the cell built
// only to be written is not built: putStrLn (pack ('>' :: header)) writes
// the character, then the header as it walks it.
// CHECK-LABEL: func.func @cell(
// CHECK-SAME: %[[H:[a-z0-9]+]]: !idr.box<@Chars>, %[[W:[a-z0-9]+]]: !idr.world)
// CHECK-NOT: idr.con @
// CHECK: %[[W1:.*]] = idr.io.put_char %{{.*}}, %[[W]]
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_list %[[H]], %[[W1]] : !idr.box<@Chars>
// CHECK-NOT: idr.con @
// CHECK: return
func.func @cell(%header: !idr.box<@Chars>, %w: !idr.world) -> !idr.world {
  %gt = arith.constant 62 : i32
  %l = idr.con @Chars::@Cons(%gt, %header) : (i32, !idr.box<@Chars>) -> !idr.box<@Chars>
  %s = idr.str.pack %l : !idr.box<@Chars> -> !idr.str
  %nl = idr.constant "\n" : !idr.str
  %t = idr.str.append %s, %nl
  %w1 = idr.io.put_str %t, %w
  return %w1 : !idr.world
}

// The cells of a list of strings: each string as put_str writes it, the
// last cell's tail a constant nil, which writes nothing.
// CHECK-LABEL: func.func @cells_of_strings(
// CHECK-SAME: %[[A:[a-z0-9]+]]: !idr.str, %[[B:[a-z0-9]+]]: !idr.str, %[[W:[a-z0-9]+]]: !idr.world)
// CHECK-NEXT: %[[W1:.*]] = idr.io.put_str %[[A]], %[[W]]
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_str %[[B]], %[[W1]]
// CHECK-NEXT: return %[[W2]]
func.func @cells_of_strings(%a: !idr.str, %b: !idr.str, %w: !idr.world) -> !idr.world {
  %nil = idr.con @Strs::@Nil() : () -> !idr.box<@Strs>
  %l1 = idr.con @Strs::@Cons(%b, %nil) : (!idr.str, !idr.box<@Strs>) -> !idr.box<@Strs>
  %l2 = idr.con @Strs::@Cons(%a, %l1) : (!idr.str, !idr.box<@Strs>) -> !idr.box<@Strs>
  %s = idr.str.concat %l2 : !idr.box<@Strs> -> !idr.str
  %w1 = idr.io.put_str %s, %w
  return %w1 : !idr.world
}

// A cell with another use is built anyway: it is written as it is walked.
// CHECK-LABEL: func.func @cell_kept(
// CHECK: %[[L:.*]] = idr.con @Chars::@Cons
// CHECK-NEXT: idr.io.put_list %[[L]]
// CHECK: return %{{.*}}, %[[L]]
func.func @cell_kept(%header: !idr.box<@Chars>, %w: !idr.world) -> (!idr.world, !idr.box<@Chars>) {
  %gt = arith.constant 62 : i32
  %l = idr.con @Chars::@Cons(%gt, %header) : (i32, !idr.box<@Chars>) -> !idr.box<@Chars>
  %w1 = idr.io.put_list %l, %w : !idr.box<@Chars>
  return %w1, %l : !idr.world, !idr.box<@Chars>
}

// Output of a string that one region of a match packs, and another takes
// as a constant, moves into the match: the region that packs writes its
// list as it walks it, the other writes its string.
// CHECK-LABEL: func.func @packed_in_a_region(
// CHECK-SAME: %[[CS:[a-z0-9]+]]: !idr.box<@Chars>, %[[W:[a-z0-9]+]]: !idr.world)
// CHECK-NOT: idr.str.pack
// CHECK: case 0 {
// CHECK-NEXT: idr.io.put_list %[[CS]], %[[W]] : !idr.box<@Chars>
// CHECK: default {
// CHECK: idr.io.put_str %{{.*}}, %[[W]]
// CHECK-NOT: idr.str.pack
// CHECK: return
func.func @packed_in_a_region(%a: i64, %cs: !idr.box<@Chars>, %w: !idr.world) -> !idr.world {
  %s = idr.match_lit %a : i64 -> (!idr.str) {
  case 0 {
    %p = idr.str.pack %cs : !idr.box<@Chars> -> !idr.str
    idr.yield %p : !idr.str
  }
  default {
    %k = idr.constant "none" : !idr.str
    idr.yield %k : !idr.str
  }
  }
  %w1 = idr.io.put_str %s, %w
  return %w1 : !idr.world
}
