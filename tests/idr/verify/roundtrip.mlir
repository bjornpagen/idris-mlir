// RUN: idris-mlir-opt %s | FileCheck %s
// RUN: idris-mlir-opt %s | idris-mlir-opt | FileCheck %s
// RUN: idris-mlir-opt %s --mlir-print-op-generic | idris-mlir-opt | FileCheck %s
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// Every op, type and attribute of the contract
// parses in its custom syntax and prints back the same, directly and from the
// generic form. A symbol that does not start with a letter is quoted: the
// contract's `@$58$$58$` is written `@"$58$$58$"`.

// NEEDS-ACCEPTANCE: the aliases the printer gives the data types and their spelling.
// CHECK-DAG: !Shape = !idr.data<"Main.Shape", plain [@Circle(f64), @Rect(f64, f64), @Proven(i64)]>
// CHECK-DAG: !List = !idr.data<"List", list [@Nil() nil, @"$58$$58$"(i64, !idr.box<!idr.data<"List">>) cons]>
// CHECK-DAG: !Fields = !idr.data<"Fields", plain [@All(i8, i16, i32, i64, f64, !idr.str, !idr.big, !idr.world, !idr.fn<(i64) -> i64>, !idr.fn<() -> ()>, !Shape, !idr.box<!List>)]>
// CHECK-LABEL: module {
!Main.Shape = !idr.data<"Main.Shape", plain [@Circle(f64), @Rect(f64, f64), @Proven(i64)]>
!List = !idr.data<"List", list [@Nil() nil, @"$58$$58$"(i64, !idr.box<!idr.data<"List">>) cons]>
!Fields = !idr.data<"Fields", plain [@All(i8, i16, i32, i64, f64, !idr.str, !idr.big, !idr.world, !idr.fn<(i64) -> (i64)>, !idr.fn<() -> ()>, !Main.Shape, !idr.box<!List>)]>
idr.program @roundtrip root(@Main.main) stage(higher) {
  idr.func @inc(%k: i64, %x: i64) -> i64 {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }

  // An array tied to the sizes Idris proved equal: a tensor before
  // bufferization, the buffer after it.
  // CHECK-LABEL: idr.func @ties
  // CHECK: {{(idr\.)?}}tie_shape %{{.*}} dims(%{{.*}}) : tensor<?x4xf64>
  // CHECK: {{(idr\.)?}}tie_shape %{{.*}} dims(%{{.*}}) : memref<?xi64>
  idr.func @ties(%t: tensor<?x4xf64>, %m: memref<?xi64>, %n: index)
      -> (tensor<?x4xf64>, memref<?xi64>) {
    %t1 = idr.tie_shape %t dims(%n) : tensor<?x4xf64>
    %m1 = idr.tie_shape %m dims(%n) : memref<?xi64>
    return %t1, %m1 : tensor<?x4xf64>, memref<?xi64>
  }

  // CHECK-LABEL: idr.func @values
  idr.func @values(%x: i64, %d: f64,
                            %s: !Main.Shape,
                            %l: !idr.box<!List>)
      -> (i64, f64, i64, i64) attributes {total} {
    // CHECK: constant #idr.con<!Shape, @Rect, [1.000000e+00, 2.000000e+00]> : !Shape
    %c0 = idr.constant #idr.con<!Main.Shape, @Rect, [1.0 : f64, 2.0 : f64]> : !Main.Shape
    // CHECK: constant #idr.con<!List, @"$58$$58$", [7, #idr.con<!List, @Nil, []>]> : !idr.box<!List>
    %c1 = idr.constant #idr.con<!List, @"$58$$58$", [7 : i64, #idr.con<!List, @Nil, []>]> : !idr.box<!List>
    // CHECK: constant #idr.closure<@inc, [1]> : !idr.fn<(i64) -> i64>
    %c2 = idr.constant #idr.closure<@inc, [1 : i64]> : !idr.fn<(i64) -> (i64)>
    // CHECK: constant #idr.big<-123456789012345678901234567890> : !idr.big
    %c3 = idr.constant #idr.big<-123456789012345678901234567890> : !idr.big
    // CHECK: constant "hello\0A" : !idr.str
    %c5 = idr.constant "hello\n" : !idr.str
    // CHECK: con !Shape @Circle(%{{.*}} : f64)
    %v0 = idr.con !Main.Shape @Circle(%d : f64)
    // CHECK: con !idr.box<!List> @"$58$$58$"(%{{.*}} : i64, %{{.*}} : !idr.box<!List>)
    %v1 = idr.con !idr.box<!List> @"$58$$58$"(%x : i64, %l : !idr.box<!List>)
    // CHECK: field %{{.*}} : !Shape @Circle[0] -> f64
    %f0 = idr.field %s : !Main.Shape @Circle[0] -> f64
    // CHECK: field %{{.*}} : !idr.box<!List> @"$58$$58$"[0] -> i64
    %f1 = idr.field %l : !idr.box<!List> @"$58$$58$"[0] -> i64
    // CHECK: tag %{{.*}} : !Shape
    %t0 = idr.tag %s : !Main.Shape
    // CHECK: tag %{{.*}} : !idr.box<!List>
    %t1 = idr.tag %l : !idr.box<!List>
    return %f1, %f0, %t0, %t1 : i64, f64, i64, i64
  }

  // CHECK-LABEL: idr.func @matches
  idr.func @matches(%s: !Main.Shape,
                             %n: i64, %c: i32,
                             %b: i1, %t: !idr.str,
                             %g: !idr.big, %w: !idr.world)
      -> (f64, !idr.world) {
    // CHECK: %{{.*}}:2 = {{(idr\.)?}}match %{{.*}} : !Shape -> (f64, !idr.world) {
    // CHECK-NEXT: case @Circle(%[[R:.*]]: f64) {
    // CHECK-NEXT: idr.yield %[[R]], %{{.*}} : f64, !idr.world
    // CHECK-NEXT: }
    // CHECK-NEXT: case @Rect(%[[W:.*]]: f64, %[[H:.*]]: f64) {
    // CHECK-NEXT: arith.mulf %[[W]], %[[H]] : f64
    // CHECK: default {
    // CHECK-NEXT: crash "unhandled input for Main.f"
    // CHECK-NEXT: ub.unreachable
    // CHECK-NEXT: }
    // CHECK-NEXT: }
    %r:2 = idr.match %s : !Main.Shape -> (f64, !idr.world) {
    case @Circle(%r: f64) {
      idr.yield %r, %w : f64, !idr.world
    }
    case @Rect(%x: f64, %y: f64) {
      %a = arith.mulf %x, %y : f64
      idr.yield %a, %w : f64, !idr.world
    }
    default {
      idr.crash "unhandled input for Main.f"
      ub.unreachable
    }
    }
    // A match of no results, and one with every region left out.
    // CHECK: match %{{.*}} : !Shape -> () {
    // CHECK-NEXT: case @Proven(%{{.*}}: i64) {
    // CHECK-NEXT: idr.yield
    // CHECK-NEXT: }
    // CHECK-NEXT: }
    idr.match %s : !Main.Shape -> () {
    case @Proven(%v: i64) {
      idr.yield
    }
    }
    // CHECK: match %{{.*}} : !Shape -> (i64) {
    // CHECK-NEXT: }
    %none = idr.match %s : !Main.Shape -> (i64) {
    }
    // CHECK: match_lit %{{.*}} : i64 -> (i64) {
    // CHECK-NEXT: case 0 {
    // CHECK: case -9223372036854775808 {
    // CHECK: default {
    %i = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    case -9223372036854775808 {
      idr.yield %n : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    // Characters are i32, flags i1.
    // CHECK: match_lit %{{.*}} : i32 -> (i64) {
    // CHECK-NEXT: case 955 {
    %j = idr.match_lit %c : i32 -> (i64) {
    case 955 {
      idr.yield %n : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    // CHECK: match_lit %{{.*}} : i1 -> (i64) {
    // CHECK-NEXT: case true {
    %k = idr.match_lit %b : i1 -> (i64) {
    case true {
      idr.yield %n : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    // CHECK: match_lit %{{.*}} : !idr.str -> (i64) {
    // CHECK-NEXT: case "" {
    // CHECK: case "a\0Ab" {
    %l = idr.match_lit %t : !idr.str -> (i64) {
    case "" {
      idr.yield %n : i64
    }
    case "a\nb" {
      idr.yield %n : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    // CHECK: match_lit %{{.*}} : !idr.big -> (i64) {
    // CHECK-NEXT: case #idr.big<0> {
    %m = idr.match_lit %g : !idr.big -> (i64) {
    case #idr.big<0> {
      idr.yield %n : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    return %r#0, %r#1 : f64, !idr.world
  }

  // CHECK-LABEL: idr.func @closures
  idr.func @closures(%x: i64) -> i64 {
    // CHECK: %[[C:.*]] = {{(idr\.)?}}closure @inc(%{{.*}}) : (i64) -> !idr.fn<(i64) -> i64>
    %c = idr.closure @inc(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    // CHECK: apply %[[C]](%{{.*}}) : !idr.fn<(i64) -> i64>
    %r = idr.apply %c(%x) : !idr.fn<(i64) -> (i64)>
    // CHECK: closure @inc() : () -> !idr.fn<(i64, i64) -> i64>
    %d = idr.closure @inc() : () -> !idr.fn<(i64, i64) -> (i64)>
    return %r : i64
  }

  // CHECK-LABEL: idr.func @scalars
  idr.func @scalars(%x: i64, %y: i8,
                             %d: f64) {
    // CHECK: div signed %{{.*}}, %{{.*}} : i64
    %a = idr.div signed %x, %x : i64
    // CHECK: mod %{{.*}}, %{{.*}} : i8
    %b = idr.mod unsigned %y, %y : i8
    // CHECK: to_char signed %{{.*}} : i64
    %c = idr.to_char signed %x : i64
    // CHECK: to_int %{{.*}} : i32
    %e = idr.to_int %d : i32
    // CHECK: double_head %{{.*}}
    %f = idr.double_head %d
    // CHECK: int_head signed %{{.*}} : i64
    %g = idr.int_head signed %x : i64
    // CHECK: int_head %{{.*}} : i8
    %h = idr.int_head %y : i8
    // CHECK: may_loop
    idr.may_loop
    return
  }

  // CHECK-LABEL: idr.func @strings
  idr.func @strings(%s: !idr.str, %c: i32,
                             %x: i64, %y: i8,
                             %d: f64) {
    // CHECK: idr.str.append %{{.*}}, %{{.*}}
    %a = idr.str.append %s, %s
    // CHECK: idr.str.cons %{{.*}}, %{{.*}}
    %b = idr.str.cons %c, %s
    // CHECK: idr.str.from_char %{{.*}}
    %e = idr.str.from_char %c
    // CHECK: idr.str.show signed %{{.*}} : i64
    %f = idr.str.show signed %x : i64
    // CHECK: idr.str.show %{{.*}} : i8
    %g = idr.str.show unsigned %y : i8
    // CHECK: idr.str.show %{{.*}} : f64
    %h = idr.str.show %d : f64
    // CHECK: idr.str.length %{{.*}}
    %i = idr.str.length %s
    // CHECK: idr.str.index %{{.*}}, %{{.*}}
    %j = idr.str.index %s, %x
    // CHECK: idr.str.head %{{.*}}
    %k = idr.str.head %s
    // CHECK: idr.str.tail %{{.*}}
    %l = idr.str.tail %s
    // CHECK: idr.str.substr %{{.*}}, %{{.*}}, %{{.*}}
    %m = idr.str.substr %s, %x, %x
    // CHECK: idr.str.reverse %{{.*}}
    %n = idr.str.reverse %s
    // CHECK: idr.str.cmp eq %{{.*}}, %{{.*}}
    %o = idr.str.cmp eq %s, %s
    // CHECK: idr.str.cmp lt
    %p = idr.str.cmp lt %s, %s
    // CHECK: idr.str.cmp lte
    %q = idr.str.cmp lte %s, %s
    // CHECK: idr.str.cmp gt
    %r = idr.str.cmp gt %s, %s
    // CHECK: idr.str.cmp gte
    %t = idr.str.cmp gte %s, %s
    // CHECK: idr.str.to_int signed %{{.*}} : i64
    %u = idr.str.to_int signed %s : i64
    // CHECK: idr.str.to_int %{{.*}} : i8
    %v = idr.str.to_int unsigned %s : i8
    // CHECK: idr.str.to_double %{{.*}}
    %w = idr.str.to_double %s
    return
  }

  // CHECK-LABEL: idr.func @bigs
  idr.func @bigs(%a: !idr.big, %x: i64,
                          %d: f64, %s: !idr.str) {
    // CHECK: idr.big.add %{{.*}}, %{{.*}}
    %0 = idr.big.add %a, %a
    // CHECK: idr.big.sub
    %1 = idr.big.sub %a, %a
    // CHECK: idr.big.mul
    %2 = idr.big.mul %a, %a
    // CHECK: idr.big.div
    %3 = idr.big.div %a, %a
    // CHECK: idr.big.mod
    %4 = idr.big.mod %a, %a
    // CHECK: idr.big.and
    %5 = idr.big.and %a, %a
    // CHECK: idr.big.or
    %6 = idr.big.or %a, %a
    // CHECK: idr.big.xor
    %7 = idr.big.xor %a, %a
    // CHECK: idr.big.neg %{{.*}}
    %8 = idr.big.neg %a
    // CHECK: idr.big.shl %{{.*}}, %{{.*}}
    %s0 = idr.big.shl %a, %a
    // CHECK: idr.big.shr %{{.*}}, %{{.*}}
    %s1 = idr.big.shr %a, %a
    // CHECK: idr.big.cmp gte %{{.*}}, %{{.*}}
    %9 = idr.big.cmp gte %a, %a
    // CHECK: idr.big.from_int signed %{{.*}} : i64
    %10 = idr.big.from_int signed %x : i64
    // CHECK: idr.big.to_int %{{.*}} : i32
    %11 = idr.big.to_int %a : i32
    // CHECK: idr.big.from_double %{{.*}}
    %12 = idr.big.from_double %d
    // CHECK: idr.big.to_double %{{.*}}
    %13 = idr.big.to_double %a
    // CHECK: idr.big.show %{{.*}}
    %14 = idr.big.show %a
    // CHECK: idr.big.from_str %{{.*}}
    %15 = idr.big.from_str %s
    return
  }

  // The big ops that keep naturals natural write the type; the others take
  // and give Integers only.
  // CHECK-LABEL: idr.func @naturals
  idr.func @naturals(%n: !idr.nat, %a: !idr.big) {
    // CHECK: constant #idr.big<3> : !idr.nat
    %three = idr.constant #idr.big<3> : !idr.nat
    // CHECK: idr.big.add %{{.*}}, %{{.*}} : !idr.nat
    %0 = idr.big.add %n, %three : !idr.nat
    // CHECK: idr.big.mul %{{.*}}, %{{.*}} : !idr.nat
    %1 = idr.big.mul %n, %n : !idr.nat
    // CHECK: idr.big.cmp lt %{{.*}}, %{{.*}} : !idr.nat
    %2 = idr.big.cmp lt %n, %three : !idr.nat
    // CHECK: idr.big.pred %{{.*}}
    %3 = idr.big.pred %n
    // CHECK: idr.nat.to_big %{{.*}}
    %4 = idr.nat.to_big %n
    // CHECK: idr.nat.from_big %{{.*}}
    %5 = idr.nat.from_big %a
    return
  }

  // An IORef is an array of rank 0: made, read, written and updated in
  // place with no size and no index. An exchange is an update whose region
  // gives the new element back and the old one out.
  // CHECK-LABEL: idr.func @ref
  idr.func @ref(%v: !idr.str, %s: !idr.str, %w0: !idr.world) -> (!idr.str, !idr.world) {
    // CHECK: idr.array.new [], %{{.*}}, %{{.*}} : !idr.str -> memref<!idr.str, #idr.world>
    %r, %w1 = idr.array.new [], %v, %w0 : !idr.str -> memref<!idr.str, #idr.world>
    // CHECK: idr.array.update %{{.*}}[], %{{.*}} {
    // CHECK: idr.array.yield %{{.*}}, %{{.*}} : !idr.str, !idr.str
    // CHECK: } : memref<!idr.str, #idr.world> -> !idr.str
    %x, %w2 = idr.array.update %r[], %w1 {
    ^bb0(%old: !idr.str):
      idr.array.yield %s, %old : !idr.str, !idr.str
    } : memref<!idr.str, #idr.world> -> !idr.str
    return %x, %w2 : !idr.str, !idr.world
  }

  // CHECK-LABEL: idr.func @Main.main
  idr.func @Main.main(%w0: !idr.world) -> !idr.world attributes {total} {
    %s = idr.constant "hi" : !idr.str
    %c = arith.constant 65 : i32
    %n = arith.constant -1 : i64
    %d = arith.constant 1.5 : f64
    // CHECK: idr.io.put_str %{{.*}}, %{{.*}}
    %w1 = idr.io.put_str %s, %w0
    // CHECK: idr.io.put_char %{{.*}}, %{{.*}}
    %w2 = idr.io.put_char %c, %w1
    // CHECK: idr.io.put_int signed %{{.*}}, %{{.*}} : i64
    %w3 = idr.io.put_int signed %n, %w2 : i64
    // CHECK: idr.io.put_double %{{.*}}, %{{.*}}
    %w4 = idr.io.put_double %d, %w3
    // CHECK: %{{.*}}, %{{.*}} = idr.io.get_byte %{{.*}}
    %by, %w5 = idr.io.get_byte %w4
    return %w5 : !idr.world
  }
}
