// RUN: idris-mlir-opt %s | FileCheck %s
// RUN: idris-mlir-opt %s | idris-mlir-opt | FileCheck %s
// RUN: idris-mlir-opt %s --mlir-print-op-generic | idris-mlir-opt | FileCheck %s
// rule: IDR-MOD-2, IDR-TY-1, IDR-TY-2, IDR-TY-4, IDR-TY-5, IDR-TY-6, IDR-TY-7, IDR-TY-8
// rule: IDR-CONST-1, IDR-CONST-2, IDR-DATA-1, IDR-DATA-2, IDR-CON-1, IDR-TAG-1, IDR-FIELD-1
// rule: IDR-MATCH-5, IDR-MATCH-6, IDR-CLOS-1, IDR-CRASH-1, IDR-STR-2, IDR-BIG-1, IDR-IO-1
// Every op, type and attribute of the contract (08-idr-dialect.md)
// parses in its custom syntax and prints back the same, directly and from the
// generic form. A symbol that does not start with a letter is quoted: the
// contract's `@$58$$58$` is written `@"$58$$58$"`.

// CHECK-LABEL: module attributes {idr.program}
module attributes {idr.program} {
  // CHECK: idr.data @Main.Shape {
  // CHECK-NEXT: idr.ctor @Circle tag 0 (f64) {quantities = ["w"]}
  // CHECK-NEXT: idr.ctor @Rect tag 1 (f64, f64) {quantities = ["w", "w"]}
  // CHECK-NEXT: idr.ctor @Proven tag 2 (!idr.erased, i64) {quantities = ["0", "1"]}
  idr.data @Main.Shape {
    idr.ctor @Circle tag 0 (f64) {quantities = ["w"]}
    idr.ctor @Rect tag 1 (f64, f64) {quantities = ["w", "w"]}
    idr.ctor @Proven tag 2 (!idr.erased, i64) {quantities = ["0", "1"]}
  }
  // CHECK: idr.data @List box {
  // CHECK-NEXT: idr.ctor @Nil tag 0 () {quantities = []}
  // CHECK-NEXT: idr.ctor @"$58$$58$" tag 1 (i64, !idr.box<@List>) {quantities = ["w", "w"]}
  idr.data @List box {
    idr.ctor @Nil tag 0 () {quantities = []}
    idr.ctor @"$58$$58$" tag 1 (i64, !idr.box<@List>) {quantities = ["w", "w"]}
  }
  // CHECK: idr.data @Fields {
  // CHECK-NEXT: idr.ctor @All tag 0 (i8, i16, i32, i64, f64, !idr.str, !idr.big, !idr.world, !idr.fn<(i64) -> (i64)>, !idr.fn<() -> ()>, !idr.data<@Main.Shape>, !idr.box<@List>)
  idr.data @Fields {
    idr.ctor @All tag 0 (i8, i16, i32, i64, f64, !idr.str, !idr.big, !idr.world,
                         !idr.fn<(i64) -> (i64)>, !idr.fn<() -> ()>,
                         !idr.data<@Main.Shape>, !idr.box<@List>)
        {quantities = ["w", "w", "w", "w", "w", "w", "w", "1", "w", "w", "w", "w"]}
  }

  func.func private @inc(%k: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }

  // CHECK-LABEL: func.func private @values
  func.func private @values(%x: i64 {idr.quantity = "w"}, %d: f64 {idr.quantity = "w"},
                            %s: !idr.data<@Main.Shape> {idr.quantity = "w"},
                            %l: !idr.box<@List> {idr.quantity = "w"})
      -> (i64, f64, i64, i64) attributes {idr.total} {
    // CHECK: idr.constant #idr.con<@Main.Shape::@Rect, [1.000000e+00, 2.000000e+00]> : !idr.data<@Main.Shape>
    %c0 = idr.constant #idr.con<@Main.Shape::@Rect, [1.0 : f64, 2.0 : f64]> : !idr.data<@Main.Shape>
    // CHECK: idr.constant #idr.con<@List::@"$58$$58$", [7, #idr.con<@List::@Nil, []>]> : !idr.box<@List>
    %c1 = idr.constant #idr.con<@List::@"$58$$58$", [7 : i64, #idr.con<@List::@Nil, []>]> : !idr.box<@List>
    // CHECK: idr.constant #idr.closure<@inc, [1]> : !idr.fn<(i64) -> (i64)>
    %c2 = idr.constant #idr.closure<@inc, [1 : i64]> : !idr.fn<(i64) -> (i64)>
    // CHECK: idr.constant #idr.big<"-123456789012345678901234567890"> : !idr.big
    %c3 = idr.constant #idr.big<"-123456789012345678901234567890"> : !idr.big
    // CHECK: idr.constant #idr.erased : !idr.erased
    %c4 = idr.constant #idr.erased : !idr.erased
    // CHECK: idr.constant "hello\0A" : !idr.str
    %c5 = idr.constant "hello\n" : !idr.str
    // CHECK: idr.con @Main.Shape::@Circle(%{{.*}}) : (f64) -> !idr.data<@Main.Shape>
    %v0 = idr.con @Main.Shape::@Circle(%d) : (f64) -> !idr.data<@Main.Shape>
    // CHECK: idr.con @List::@"$58$$58$"(%{{.*}}, %{{.*}}) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %v1 = idr.con @List::@"$58$$58$"(%x, %l) : (i64, !idr.box<@List>) -> !idr.box<@List>
    // CHECK: idr.field %{{.*}}[@Circle, 0] : !idr.data<@Main.Shape> -> f64
    %f0 = idr.field %s[@Circle, 0] : !idr.data<@Main.Shape> -> f64
    // CHECK: idr.field %{{.*}}[@"$58$$58$", 0] : !idr.box<@List> -> i64
    %f1 = idr.field %l[@"$58$$58$", 0] : !idr.box<@List> -> i64
    // CHECK: idr.tag %{{.*}} : !idr.data<@Main.Shape>
    %t0 = idr.tag %s : !idr.data<@Main.Shape>
    // CHECK: idr.tag %{{.*}} : !idr.box<@List>
    %t1 = idr.tag %l : !idr.box<@List>
    return %f1, %f0, %t0, %t1 : i64, f64, i64, i64
  }

  // CHECK-LABEL: func.func private @matches
  func.func private @matches(%s: !idr.data<@Main.Shape> {idr.quantity = "w"},
                             %n: i64 {idr.quantity = "w"}, %c: i32 {idr.quantity = "w"},
                             %b: i1 {idr.quantity = "w"}, %t: !idr.str {idr.quantity = "w"},
                             %g: !idr.big {idr.quantity = "w"}, %w: !idr.world {idr.quantity = "1"})
      -> (f64, !idr.world) {
    // CHECK: %{{.*}}:2 = idr.match %{{.*}} : !idr.data<@Main.Shape> -> (f64, !idr.world) {
    // CHECK-NEXT: case @Circle(%[[R:.*]]: f64) {
    // CHECK-NEXT: idr.yield %[[R]], %{{.*}} : f64, !idr.world
    // CHECK-NEXT: }
    // CHECK-NEXT: case @Rect(%[[W:.*]]: f64, %[[H:.*]]: f64) {
    // CHECK-NEXT: arith.mulf %[[W]], %[[H]] : f64
    // CHECK: default {
    // CHECK-NEXT: idr.crash "unhandled input for Main.f"
    // CHECK-NEXT: ub.unreachable
    // CHECK-NEXT: }
    // CHECK-NEXT: }
    %r:2 = idr.match %s : !idr.data<@Main.Shape> -> (f64, !idr.world) {
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
    // CHECK: idr.match %{{.*}} : !idr.data<@Main.Shape> -> () {
    // CHECK-NEXT: case @Proven(%{{.*}}: !idr.erased, %{{.*}}: i64) {
    // CHECK-NEXT: idr.yield
    // CHECK-NEXT: }
    // CHECK-NEXT: }
    idr.match %s : !idr.data<@Main.Shape> -> () {
    case @Proven(%e: !idr.erased, %v: i64) {
      idr.yield
    }
    }
    // CHECK: idr.match %{{.*}} : !idr.data<@Main.Shape> -> (i64) {
    // CHECK-NEXT: }
    %none = idr.match %s : !idr.data<@Main.Shape> -> (i64) {
    }
    // CHECK: idr.match_lit %{{.*}} : i64 -> (i64) {
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
    // CHECK: idr.match_lit %{{.*}} : i32 -> (i64) {
    // CHECK-NEXT: case 955 {
    %j = idr.match_lit %c : i32 -> (i64) {
    case 955 {
      idr.yield %n : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    // CHECK: idr.match_lit %{{.*}} : i1 -> (i64) {
    // CHECK-NEXT: case true {
    %k = idr.match_lit %b : i1 -> (i64) {
    case true {
      idr.yield %n : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    // CHECK: idr.match_lit %{{.*}} : !idr.str -> (i64) {
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
    // CHECK: idr.match_lit %{{.*}} : !idr.big -> (i64) {
    // CHECK-NEXT: case #idr.big<"0"> {
    %m = idr.match_lit %g : !idr.big -> (i64) {
    case #idr.big<"0"> {
      idr.yield %n : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    return %r#0, %r#1 : f64, !idr.world
  }

  // CHECK-LABEL: func.func private @closures
  func.func private @closures(%x: i64 {idr.quantity = "w"}) -> i64 {
    // CHECK: %[[C:.*]] = idr.closure @inc(%{{.*}}) : (i64) -> !idr.fn<(i64) -> (i64)>
    %c = idr.closure @inc(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    // CHECK: idr.apply %[[C]](%{{.*}}) : !idr.fn<(i64) -> (i64)>
    %r = idr.apply %c(%x) : !idr.fn<(i64) -> (i64)>
    // CHECK: idr.closure @inc() : () -> !idr.fn<(i64, i64) -> (i64)>
    %d = idr.closure @inc() : () -> !idr.fn<(i64, i64) -> (i64)>
    return %r : i64
  }

  // CHECK-LABEL: func.func private @scalars
  func.func private @scalars(%x: i64 {idr.quantity = "w"}, %y: i8 {idr.quantity = "w"},
                             %d: f64 {idr.quantity = "w"}) {
    // CHECK: idr.div signed %{{.*}}, %{{.*}} : i64
    %a = idr.div signed %x, %x : i64
    // CHECK: idr.mod %{{.*}}, %{{.*}} : i8
    %b = idr.mod unsigned %y, %y : i8
    // CHECK: idr.to_char signed %{{.*}} : i64
    %c = idr.to_char signed %x : i64
    // CHECK: idr.to_int %{{.*}} : i32
    %e = idr.to_int %d : i32
    // CHECK: idr.double_head %{{.*}}
    %f = idr.double_head %d
    // CHECK: idr.int_head signed %{{.*}} : i64
    %g = idr.int_head signed %x : i64
    // CHECK: idr.int_head %{{.*}} : i8
    %h = idr.int_head %y : i8
    // CHECK: idr.may_loop
    idr.may_loop
    return
  }

  // CHECK-LABEL: func.func private @strings
  func.func private @strings(%s: !idr.str {idr.quantity = "w"}, %c: i32 {idr.quantity = "w"},
                             %x: i64 {idr.quantity = "w"}, %y: i8 {idr.quantity = "w"},
                             %d: f64 {idr.quantity = "w"}) {
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

  // CHECK-LABEL: func.func private @bigs
  func.func private @bigs(%a: !idr.big {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"},
                          %d: f64 {idr.quantity = "w"}, %s: !idr.str {idr.quantity = "w"}) {
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

  // CHECK-LABEL: func.func @Main.main
  func.func @Main.main(%w0: !idr.world {idr.quantity = "1"}) -> !idr.world attributes {idr.total} {
    %s = idr.constant "hi" : !idr.str
    %c = arith.constant 65 : i32
    %n = arith.constant -1 : i64
    %d = arith.constant 1.5 : f64
    %z = arith.constant 0 : i64
    // CHECK: idr.io.put_str %{{.*}}, %{{.*}}
    %w1 = idr.io.put_str %s, %w0
    // CHECK: idr.io.put_char %{{.*}}, %{{.*}}
    %w2 = idr.io.put_char %c, %w1
    // CHECK: idr.io.put_int signed %{{.*}}, %{{.*}} : i64
    %w3 = idr.io.put_int signed %n, %w2 : i64
    // CHECK: idr.io.put_double %{{.*}}, %{{.*}}
    %w4 = idr.io.put_double %d, %w3
    // CHECK: %{{.*}}, %{{.*}} = idr.io.get_char %{{.*}}
    %ch, %w5 = idr.io.get_char %w4
    // CHECK: %{{.*}}, %{{.*}} = idr.io.get_byte %{{.*}}
    %by, %w6 = idr.io.get_byte %w5
    // CHECK: idr.io.exit %{{.*}}, %{{.*}}
    %w7 = idr.io.exit %z, %w6
    return %w7 : !idr.world
  }
}
