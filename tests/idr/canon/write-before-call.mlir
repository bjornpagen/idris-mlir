// RUN: idris-mlir-opt %s --idr-effects --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --idr-effects --canonicalize --idr-effects --canonicalize | FileCheck %s
// A function that writes a string parameter before anything else it does
// with the world, as a `show` that builds its result in an accumulator does
// once it writes it, gets that string written by its caller instead: a
// string built at runtime is written piece by piece where it is built, not
// passed on. Where the function might write something else first, crash or
// not return, or where the string is not what it writes first, the call
// stays. Running both passes again changes nothing.

// count acc n = if n == 0 then acc else count (acc ++ show n ++ " ") (n - 1),
// written: the accumulator is written first on every path, the one of the
// recursive call included. In the recursion each piece is written as it is
// built, and the recursive call gets the empty string.
// CHECK-LABEL: func.func private @count(
// CHECK-SAME: %[[ACC:[^:]*]]: !idr.str {idr.writes_first}, %[[N:[^:]*]]: i64, %[[W:[^:]*]]: !idr.world)
// CHECK-NOT: idr.str.
// CHECK: default {
// CHECK: %[[W1:.*]] = idr.io.put_str %[[ACC]], %[[W]]
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_int signed %[[N]], %[[W1]]
// CHECK-NEXT: %[[W3:.*]] = idr.io.put_str %{{.*}}, %[[W2]]
// CHECK: call @count(%{{.*}}, %{{.*}}, %[[W3]])
// CHECK-NOT: idr.str.
// CHECK: return
func.func private @count(%acc: !idr.str, %n: i64, %w: !idr.world) -> !idr.world
    attributes {idr.total} {
  %r = idr.match_lit %n : i64 -> (!idr.world) {
  case 0 {
    %w1 = idr.io.put_str %acc, %w
    idr.yield %w1 : !idr.world
  }
  default {
    %one = arith.constant 1 : i64
    %m = arith.subi %n, %one : i64
    %space = idr.constant " " : !idr.str
    %s = idr.str.show signed %n : i64
    %t = idr.str.append %s, %space
    %u = idr.str.append %acc, %t
    %w1 = func.call @count(%u, %m, %w) : (!idr.str, i64, !idr.world) -> !idr.world
    idr.yield %w1 : !idr.world
  }
  }
  return %r : !idr.world
}

// The caller writes "[" and the number, then calls with the empty string.
// CHECK-LABEL: func.func @write_count(
// CHECK-SAME: %[[N:[^:]*]]: i64, %[[W:[^:]*]]: !idr.world)
// CHECK-NOT: idr.str.
// CHECK-DAG: %[[EMPTY:.*]] = idr.constant "" : !idr.str
// CHECK-DAG: %[[W1:.*]] = idr.io.put_str %{{.*}}, %[[W]]
// CHECK: %[[W2:.*]] = idr.io.put_int signed %[[N]], %[[W1]]
// CHECK-NEXT: %[[W3:.*]] = call @count(%[[EMPTY]], %[[N]], %[[W2]])
// CHECK-NEXT: return %[[W3]]
func.func @write_count(%n: i64, %w: !idr.world) -> !idr.world {
  %open = idr.constant "[" : !idr.str
  %s = idr.str.show signed %n : i64
  %t = idr.str.append %open, %s
  %w1 = func.call @count(%t, %n, %w) : (!idr.str, i64, !idr.world) -> !idr.world
  return %w1 : !idr.world
}

// The same, not known to return: writing the string early could show output
// the program never gets to. The string stays an argument.
// CHECK-LABEL: func.func private @count_partial(
// CHECK-NOT: idr.writes_first
// CHECK-SAME: ) -> !idr.world attributes
// CHECK-LABEL: func.func @write_count_partial(
// CHECK: %[[T:.*]] = idr.str.append
// CHECK-NEXT: call @count_partial(%[[T]],
func.func private @count_partial(%acc: !idr.str, %n: i64, %w: !idr.world) -> !idr.world {
  %r = idr.match_lit %n : i64 -> (!idr.world) {
  case 0 {
    %w1 = idr.io.put_str %acc, %w
    idr.yield %w1 : !idr.world
  }
  default {
    %one = arith.constant 1 : i64
    %m = arith.subi %n, %one : i64
    %s = idr.str.show signed %n : i64
    %u = idr.str.append %acc, %s
    %w1 = func.call @count_partial(%u, %m, %w) : (!idr.str, i64, !idr.world) -> !idr.world
    idr.yield %w1 : !idr.world
  }
  }
  return %r : !idr.world
}
func.func @write_count_partial(%n: i64, %w: !idr.world) -> !idr.world {
  %open = idr.constant "[" : !idr.str
  %s = idr.str.show signed %n : i64
  %t = idr.str.append %open, %s
  %w1 = func.call @count_partial(%t, %n, %w) : (!idr.str, i64, !idr.world) -> !idr.world
  return %w1 : !idr.world
}

// The accumulator goes at the end of what the recursion passes on, not at
// the start: it is not what the function writes first. The call stays.
// CHECK-LABEL: func.func private @count_reversed(
// CHECK-NOT: idr.writes_first
// CHECK-SAME: ) -> !idr.world attributes
// CHECK-LABEL: func.func @write_count_reversed(
// CHECK: %[[T:.*]] = idr.str.append
// CHECK-NEXT: call @count_reversed(%[[T]],
func.func private @count_reversed(%acc: !idr.str, %n: i64, %w: !idr.world) -> !idr.world
    attributes {idr.total} {
  %r = idr.match_lit %n : i64 -> (!idr.world) {
  case 0 {
    %w1 = idr.io.put_str %acc, %w
    idr.yield %w1 : !idr.world
  }
  default {
    %one = arith.constant 1 : i64
    %m = arith.subi %n, %one : i64
    %s = idr.str.show signed %n : i64
    %u = idr.str.append %s, %acc
    %w1 = func.call @count_reversed(%u, %m, %w) : (!idr.str, i64, !idr.world) -> !idr.world
    idr.yield %w1 : !idr.world
  }
  }
  return %r : !idr.world
}
func.func @write_count_reversed(%n: i64, %w: !idr.world) -> !idr.world {
  %open = idr.constant "[" : !idr.str
  %s = idr.str.show signed %n : i64
  %t = idr.str.append %open, %s
  %w1 = func.call @count_reversed(%t, %n, %w) : (!idr.str, i64, !idr.world) -> !idr.world
  return %w1 : !idr.world
}

// A path that writes something else first: the call stays.
// CHECK-LABEL: func.func private @label_first(
// CHECK-NOT: idr.writes_first
// CHECK-SAME: ) -> !idr.world attributes
// CHECK-LABEL: func.func @write_label_first(
// CHECK: %[[T:.*]] = idr.str.append
// CHECK-NEXT: call @label_first(%[[T]],
func.func private @label_first(%s: !idr.str, %w: !idr.world) -> !idr.world
    attributes {idr.total} {
  %label = idr.constant "s = " : !idr.str
  %w1 = idr.io.put_str %label, %w
  %w2 = idr.io.put_str %s, %w1
  return %w2 : !idr.world
}
func.func @write_label_first(%n: i64, %w: !idr.world) -> !idr.world {
  %open = idr.constant "[" : !idr.str
  %s = idr.str.show signed %n : i64
  %t = idr.str.append %open, %s
  %w1 = func.call @label_first(%t, %w) : (!idr.str, !idr.world) -> !idr.world
  return %w1 : !idr.world
}
