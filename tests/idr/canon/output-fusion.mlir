// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// rule: IDR-IO-1, IDR-DBL-2, ELIM-G-7
// A2: a string built only to be written is written piece by piece, in the
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
