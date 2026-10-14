// RUN: idris-mlir-opt %s --idr-deduplicate | FileCheck %s
// What is not one function twice over stays twice: a public pair (its
// names are the program's), a pair of which only one is total and a pair
// whose effects differ (a fact a call of the one kept would state of
// both), a pair that are instances of definitions (each name
// is a provenance a check may look up), a pair whose bodies differ, and
// a pair of clones, whose keys name what each specializes.
// CHECK-DAG: idr.func @pub1(
// CHECK-DAG: idr.func @pub2(
// CHECK-DAG: idr.func private @A.tot(
// CHECK-DAG: idr.func private @B.tot(
// CHECK-DAG: idr.func private @A.eff(
// CHECK-DAG: idr.func private @B.eff(
// CHECK-DAG: idr.func private @A.inst(
// CHECK-DAG: idr.func private @B.inst(
// CHECK-DAG: idr.func private @A.inc(
// CHECK-DAG: idr.func private @B.dec(
// CHECK-DAG: idr.func private @A.spec(
// CHECK-DAG: idr.func private @B.spec(
module {
  idr.func @pub1(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @pub2(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func private @A.tot(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func private @B.tot(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func private @A.eff(%x: i64) -> i64 attributes {effects = #idr.effects<none>} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func private @B.eff(%x: i64) -> i64 attributes {effects = #idr.effects<crash>} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func private @A.inst(%x: i64) -> i64 attributes {instance = #idr.instance<"Prog.fA", ["Int"]>, total} {
    return %x : i64
  }
  idr.func private @B.inst(%x: i64) -> i64 attributes {instance = #idr.instance<"Prog.fB", ["Int"]>, total} {
    return %x : i64
  }
  idr.func private @A.inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func private @B.dec(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.subi %x, %c : i64
    return %y : i64
  }
  idr.func private @A.spec(%x: i64) -> i64 attributes {clone = #idr.clone<@A.spec, #idr.spec_key<"Prog.f", [#idr.key_hole<0>]>>, total} {
    %c = arith.constant 2 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func private @B.spec(%x: i64) -> i64 attributes {clone = #idr.clone<@B.spec, #idr.spec_key<"Prog.g", [#idr.key_hole<0>]>>, total} {
    %c = arith.constant 2 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 7 : i64
    %a = idr.call @pub1(%n) : (i64) -> i64
    %b = idr.call @pub2(%a) : (i64) -> i64
    %c = idr.call @A.tot(%b) : (i64) -> i64
    %d = idr.call @B.tot(%c) : (i64) -> i64
    %e = idr.call @A.eff(%d) : (i64) -> i64
    %f = idr.call @B.eff(%e) : (i64) -> i64
    %f1 = idr.call @A.inst(%f) : (i64) -> i64
    %f2 = idr.call @B.inst(%f1) : (i64) -> i64
    %g = idr.call @A.inc(%f2) : (i64) -> i64
    %h = idr.call @B.dec(%g) : (i64) -> i64
    %i = idr.call @A.spec(%h) : (i64) -> i64
    %r = idr.call @B.spec(%i) : (i64) -> i64
    %w2 = idr.io.put_int signed %r, %w : i64
    return %w2 : !idr.world
  }
}
