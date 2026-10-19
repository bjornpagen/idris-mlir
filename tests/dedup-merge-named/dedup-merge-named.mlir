// RUN: idris-mlir-opt %s --idr-deduplicate --idr-expect=holds=one-clone=@a,one-clone=@b -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-deduplicate --idr-expect=holds=not-called=@b -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// CHECK: expected not-called: @b {{.*}}@A.inst
// Two instances of different definitions whose code is one function
// merge: which definition a function came from is provenance, read by no
// pass, and a test API never keeps two copies apart. The one kept, the
// smaller name, takes the location of both, so a property stated of
// either definition, here by the names its locations carry, finds the one
// function: every call of either reaches one function, and the code of
// @b is still called, as @A.inst.
idr.program @"merge-named" root(@root) stage(higher) {
  idr.func @A.inst(%x: i64) -> i64 attributes {instance = #idr.instance<"Prog.fA", ["Int"]>, total} {
    %c = arith.constant 3 : i64
    %y = arith.muli %x, %c : i64
    return %y : i64
  } loc("a")
  idr.func @B.inst(%x: i64) -> i64 attributes {instance = #idr.instance<"Prog.fB", ["Int"]>, total} {
    %c = arith.constant 3 : i64
    %y = arith.muli %x, %c : i64
    return %y : i64
  } loc("b")
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 7 : i64
    %a = idr.call @A.inst(%n) : (i64) -> i64
    %b = idr.call @B.inst(%a) : (i64) -> i64
    %w2 = idr.io.put_sint %b, %w : i64
    return %w2 : !idr.world
  }
}
