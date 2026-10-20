// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=forces-nothing=@choose,builds-nothing=@choose,\
// RUN: calls=@choose:@else,calls=@choose:@then,forces=@constant,calls=@constant:@then,\
// RUN: forces=@shared,builds=@shared,calls=@shared:@then -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=forces-nothing=@choose,builds-nothing=@choose,calls=@choose:@else,calls=@choose:@then,calls=@constant:@then,calls=@shared:@then' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=forces=@choose' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=builds=@choose' -o /dev/null
// BEFORE-DAG: expected forces-nothing: {{.*}}@choose
// BEFORE-DAG: expected builds-nothing: {{.*}}@choose
// BEFORE-DAG: expected calls: @choose {{.*}}@else
// BEFORE-DAG: expected calls: @choose {{.*}}@then
// BEFORE-DAG: expected calls: @constant {{.*}}@then
// BEFORE-DAG: expected calls: @shared {{.*}}@then
// `if b then f x else g x` takes its branches as suspensions: the match
// chooses one, and it is forced after the match. The force moves into the
// match's regions, where it meets the suspension its region built, built
// there or constant, which nothing else uses: each region calls its
// branch, and no cell is built. A loop through a branch is then a call,
// which the call graph sees.
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it, and @choose neither forces nor builds
// after it.
idr.program @"force-of-choice" root(@root) stage(higher) types #idr.types<> {
  idr.func @then(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @else(%x: i64) -> i64 attributes {total} {
    %c2 = arith.constant 2 : i64
    %y = arith.muli %x, %c2 : i64
    return %y : i64
  }
  idr.func @choose(%b: i64, %x: i64) -> i64 {
    %s = idr.match_lit %b : i64 -> (!idr.lazy<i64>) {
    case 0 {
      %t = idr.suspend @else(%x) : (i64) -> !idr.lazy<i64>
      idr.yield %t : !idr.lazy<i64>
    }
    default(%d: i64) {
      %t = idr.suspend @then(%x) : (i64) -> !idr.lazy<i64>
      idr.yield %t : !idr.lazy<i64>
    }
    }
    %r = idr.force %s : !idr.lazy<i64> -> i64
    return %r : i64
  }

  // A suspension of constants folds to a constant, one cell in static data,
  // whose force runs its label once: that force stays. The region that built
  // its suspension calls its branch.
  idr.func @constant(%b: i64, %x: i64) -> i64 {
    %s = idr.match_lit %b : i64 -> (!idr.lazy<i64>) {
    case 0 {
      %c3 = arith.constant 3 : i64
      %t = idr.suspend @else(%c3) : (i64) -> !idr.lazy<i64>
      idr.yield %t : !idr.lazy<i64>
    }
    default(%d: i64) {
      %t = idr.suspend @then(%x) : (i64) -> !idr.lazy<i64>
      idr.yield %t : !idr.lazy<i64>
    }
    }
    %r = idr.force %s : !idr.lazy<i64> -> i64
    return %r : i64
  }

  // A suspension its region forces too is shared: the later force reads the
  // cell the first one filled. That region keeps the cell and forces it
  // twice; only the other region calls.
  idr.func @shared(%b: i64, %x: i64) -> i64 {
    %s:2 = idr.match_lit %b : i64 -> (!idr.lazy<i64>, i64) {
    case 0 {
      %t = idr.suspend @else(%x) : (i64) -> !idr.lazy<i64>
      %u = idr.force %t : !idr.lazy<i64> -> i64
      idr.yield %t, %u : !idr.lazy<i64>, i64
    }
    default(%d: i64) {
      %t = idr.suspend @then(%x) : (i64) -> !idr.lazy<i64>
      %c0 = arith.constant 0 : i64
      idr.yield %t, %c0 : !idr.lazy<i64>, i64
    }
    }
    %r = idr.force %s#0 : !idr.lazy<i64> -> i64
    %y = arith.addi %r, %s#1 : i64
    return %y : i64
  }
  // The program's root runs every function above on what it reads, the
  // byte's low bit choosing each branch.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %b = arith.andi %x, %c1 : i64
    %r0 = idr.call @choose(%b, %x) : (i64, i64) -> i64
    %w1 = idr.io.put_sint %r0, %w0 : i64
    %r1 = idr.call @constant(%b, %x) : (i64, i64) -> i64
    %w2 = idr.io.put_sint %r1, %w1 : i64
    %r2 = idr.call @shared(%b, %x) : (i64, i64) -> i64
    %w3 = idr.io.put_sint %r2, %w2 : i64
    return %w3 : !idr.world
  }
}
