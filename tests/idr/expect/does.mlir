// NEEDS-ACCEPTANCE: that each of Does.cpp's properties holds of the function that does what it says and fails, once, on its complement.
// RUN: idris-mlir-opt %s --idr-expect=holds=matches=@takes,matches-nothing=@plain,forces=@forces,\
// RUN: forces-nothing=@plain,builds=@builds,builds-nothing=@plain,reads-fields=@reads,reads-no-fields=@takes,\
// RUN: applies=@applies,never-returns=@never,calls=@caller:@leaf,never-calls=@plain:@leaf,\
// RUN: calls-closed=@closed:@leaf -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=matches=@plain,matches-nothing=@takes,forces=@plain,\
// RUN: forces-nothing=@forces,builds=@plain,builds-nothing=@builds,reads-fields=@plain,reads-no-fields=@reads,\
// RUN: applies=@plain,never-returns=@plain,calls=@plain:@leaf,never-calls=@closed:@leaf,\
// RUN: calls-closed=@caller:@leaf -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 13
// What a function does when it runs, each stated of a function that does
// it and failing on one that does not: @plain only computes; the others
// each take a value apart, read a field, build a value, force, apply,
// crash, or call @leaf on what they are given or on a constant.
// CHECK-DAG: error: expected matches: nothing in @plain takes a value apart
// CHECK-DAG: error: expected matches-nothing: {{.*}} takes a value apart in @takes
// CHECK-DAG: error: expected forces: nothing in @plain forces a suspension
// CHECK-DAG: error: expected forces-nothing: {{.*}} forces a suspension in @forces
// CHECK-DAG: error: expected builds: nothing in @plain builds a value
// CHECK-DAG: error: expected builds-nothing: {{.*}} builds a value in @builds
// CHECK-DAG: error: expected reads-fields: nothing in @plain reads a field
// CHECK-DAG: error: expected reads-no-fields: {{.*}} reads a field in @reads
// CHECK-DAG: error: expected applies: nothing in @plain applies a closure
// CHECK-DAG: error: expected never-returns: @plain returns
// CHECK-DAG: error: expected calls: @plain calls no {{.*}}
// CHECK-DAG: error: expected never-calls: @closed still calls {{.*}}, as {{.*}}
// CHECK-DAG: error: expected calls-closed: a call of {{.*}} in @caller takes an argument that is not a constant
!Maybe = !idr.data<"Maybe", plain [@Nothing(), @Just(i64)]>
!Pair = !idr.data<"Pair", plain [@MkPair(i64, i64)]>
idr.program @does root(@root) stage(higher) {
  idr.func @plain(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @takes(%m: !Maybe) -> i64 {
    %r = idr.match %m : !Maybe -> (i64) {
    case @Just(%x: i64) {
      idr.yield %x : i64
    }
    default {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @reads(%p: !Pair) -> i64 {
    %a = idr.field %p : !Pair @MkPair[0] -> i64
    return %a : i64
  }
  idr.func @builds(%x: i64) -> !Pair {
    %p = idr.con !Pair @MkPair(%x : i64, %x : i64)
    return %p : !Pair
  }
  idr.func @forces(%t: !idr.lazy<i64>) -> i64 {
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @applies(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @never(%x: i64) -> i64 {
    idr.crash "unhandled input for never"
    ub.unreachable
  }
  idr.func @leaf(%x: i64) -> i64 {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func @caller(%x: i64) -> i64 {
    %y = idr.call @leaf(%x) : (i64) -> i64
    return %y : i64
  }
  idr.func @closed() -> i64 {
    %c = arith.constant 7 : i64
    %y = idr.call @leaf(%c) : (i64) -> i64
    return %y : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
