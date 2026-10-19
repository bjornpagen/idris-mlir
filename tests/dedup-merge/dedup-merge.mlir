// RUN: idris-mlir-opt %s --idr-expect=holds=apart=@A.inc:@B.inc,apart=@A.id:@B.id,apart=@A.down:@B.down,apart=@A.twice:@B.twice -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-deduplicate --idr-expect=holds=apart=@A.inc:@B.inc,apart=@A.id:@B.id,apart=@A.down:@B.down,apart=@A.twice:@B.twice -o /dev/null 2> %t.merged.err
// RUN: FileCheck %s --check-prefix=MERGED < %t.merged.err
// RUN: idris-mlir-opt %s --idr-deduplicate -o %t.mlir
// RUN: idris-mlir-opt %s --idr-deduplicate --mlir-disable-threading -o %t.serial.mlir
// RUN: cmp %t.mlir %t.serial.mlir
// RUN: idris-mlir-opt %t.mlir --idr-deduplicate -o %t.again.mlir
// RUN: diff %t.mlir %t.again.mlir
// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --idr-deduplicate --mlir-disable-threading -mlir-debug-counter=idr-deduplicate-merge-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: %differential %s %t.mlir
// MERGED-DAG: expected apart: {{.*}}@A.inc{{.*}}@B.inc
// MERGED-DAG: expected apart: {{.*}}@A.id{{.*}}@B.id
// MERGED-DAG: expected apart: {{.*}}@A.down{{.*}}@B.down
// MERGED-DAG: expected apart: {{.*}}@A.twice{{.*}}@B.twice
// Private functions that are one function twice over become one, the
// member with the smallest name kept: the module before the pass holds
// each pair apart, and the one after it does not. @B.inc is @A.inc, @B.id
// is @A.id, two outlines of one body, and @B.down is @A.down though each
// calls itself by its own name. Merging is transitive in one run: @B.twice
// calls @B.inc where @A.twice calls @A.inc, so once those are one, so are
// the two callers. A call, and a closure naming one of them, name the one
// kept, whose location fuses its members' (so either name finds it). The
// output is the same under one thread, a second run changes nothing, and
// with every merge skipped the pass is the identity. The root runs every
// function on what it reads, and the program prints after the pass what
// it printed before, on every byte.
idr.program @merge root(@root) stage(higher) {
  idr.func @A.inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  } loc("A.inc")
  idr.func @B.inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  } loc("B.inc")
  idr.func @A.twice(%x: i64) -> i64 attributes {total} {
    %y = idr.call @A.inc(%x) : (i64) -> i64
    %z = idr.call @A.inc(%y) : (i64) -> i64
    return %z : i64
  } loc("A.twice")
  idr.func @B.twice(%x: i64) -> i64 attributes {total} {
    %y = idr.call @B.inc(%x) : (i64) -> i64
    %z = idr.call @B.inc(%y) : (i64) -> i64
    return %z : i64
  } loc("B.twice")
  idr.func @A.id(%x: i64) -> i64 attributes {total} {
    return %x : i64
  } loc("A.id")
  idr.func @B.id(%x: i64) -> i64 attributes {total} {
    return %x : i64
  } loc("B.id")
  idr.func @A.down(%n: i64, %acc: i64) -> i64 attributes {total} {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default(%d: i1) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %s = arith.addi %acc, %n : i64
      %t = idr.call @A.down(%m, %s) : (i64, i64) -> i64
      idr.yield %t : i64
    }
    }
    return %r : i64
  } loc("A.down")
  idr.func @B.down(%n: i64, %acc: i64) -> i64 attributes {total} {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default(%d: i1) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %s = arith.addi %acc, %n : i64
      %t = idr.call @B.down(%m, %s) : (i64, i64) -> i64
      idr.yield %t : i64
    }
    }
    return %r : i64
  } loc("B.down")
  idr.func @root(%w0: !idr.world) -> !idr.world {
    %ch, %w = idr.io.get_byte %w0
    %n = arith.extui %ch : i32 to i64
    %z = arith.constant 0 : i64
    %a = idr.call @A.inc(%n) : (i64) -> i64
    %b = idr.call @B.inc(%a) : (i64) -> i64
    %f = idr.closure @B.inc() : () -> !idr.fn<(i64) -> (i64)>
    %c = idr.apply %f(%b) : !idr.fn<(i64) -> (i64)>
    %d = idr.call @B.id(%c) : (i64) -> i64
    %e = idr.call @A.down(%d, %z) : (i64, i64) -> i64
    %r0 = idr.call @B.down(%e, %z) : (i64, i64) -> i64
    %r1 = idr.call @A.twice(%r0) : (i64) -> i64
    %r = idr.call @B.twice(%r1) : (i64) -> i64
    %w2 = idr.io.put_sint %r, %w : i64
    return %w2 : !idr.world
  }
}
