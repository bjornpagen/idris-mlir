// NEEDS-ACCEPTANCE: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before.
// RUN: rm -rf %t.d && mkdir -p %t.d
// RUN: idris-mlir -c %s -o %t.o --mlir-disable-threading -mlir-print-ir-module-scope -mlir-print-ir-after-all -mlir-print-ir-tree-dir=%t.d
// RUN: sh -c 'for f in squares eighth inexact rows; do cp %t.d/builtin_module_no-symbol-name/func_func_$f/*_idr-narrow-lanes.mlir %t.$f.mlir || exit 1; done'
// RUN: sh -c 'for f in squares eighth inexact rows; do idris-mlir-opt %t.$f.mlir --transform-interpreter=entry-point=idr.vectorization.cleanup -o /dev/null || exit 1; done'
// RUN: idris-mlir-opt %t.squares.mlir --idr-expect=holds=narrowed-lanes=@squares -o /dev/null
// RUN: idris-mlir-opt %t.rows.mlir --idr-expect=holds=narrowed-lanes=@rows -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.eighth.mlir --idr-expect=holds=narrowed-lanes=@eighth -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=WIDE < %t.err
// RUN: %status 1 idris-mlir-opt %t.inexact.mlir --idr-expect=holds=narrowed-lanes=@inexact -o /dev/null 2> %t.inexact
// RUN: FileCheck %s --check-prefix=INEXACT < %t.inexact
// NEEDS-ACCEPTANCE: the tree printer's file names for a function.
// NEEDS-ACCEPTANCE: that the schedule library's unit-dimension cleanup (@idr.vectorization.cleanup), run again with its failure not suppressed on each function as idr-narrow-lanes left it, after the schedule, converges within its budget.
// After idr-narrow-lanes a vectorized loop whose body computes on the
// 64-bit index has two versions: when the sizes it reads are at most a
// bound (one test on entry), a copy whose integer lanes are i32, the
// sizes behind arith.minui so that the analysis knows the bound;
// otherwise the loop as it was, on i64 lanes (and the loop of the last
// tile, which runs once, keeps its i64 lanes). The bound is the body's:
// the squares fit i32 below 2^15, the rows' (i + j) * (i + j + 1) below
// 2^14, its division by 2 floored as Idris's `div` is. A body no bound
// above 2^8 makes fit (the eighth power) stays one loop on 64-bit lanes.
// An op whose 32-bit form would compute something else keeps its 64-bit
// lanes, in a version or not, whatever the ops around it do (@inexact): a
// shift by up to 40, poison on i32; a signed remainder that sees
// INT32_MIN % -1, which overflows on i32; an unsigned remainder of a word
// that is negative, read as another number on i32. Each function keeps
// its own body (no_inline), read in the module printed after
// idr-narrow-lanes ran on it.
// The lanes are x86-64-v3's four, the x86-64
// target entry's CPU.
// WIDE: error: expected narrowed-lanes: a loop computes integer lanes of 64 bits with no 32-bit version in @eighth
// INEXACT: error: expected narrowed-lanes: a loop computes integer lanes of 64 bits with no 32-bit version in @inexact
idr.program @"lanes-x86-64" root(@root) stage(higher) {
  idr.func @squares(%n: index) -> tensor<?xi64> attributes {total, no_inline} {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %sq = arith.muli %x, %x : i64
      %a1 = tensor.insert %sq into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    return %r : tensor<?xi64>
  }
  idr.func @eighth(%n: index) -> tensor<?xi64> attributes {total, no_inline} {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %sq = arith.muli %x, %x : i64
      %fourth = arith.muli %sq, %sq : i64
      %eighth = arith.muli %fourth, %fourth : i64
      %a1 = tensor.insert %eighth into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    return %r : tensor<?xi64>
  }
  idr.func @inexact(%n: index) -> (tensor<?xi64>, tensor<?xi64>, tensor<?xi64>) attributes {total, no_inline} {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %zero = arith.constant 0 : i64
    %c41 = arith.constant 41 : i64
    %below = arith.constant -2147483649 : i64
    %two = arith.constant 2 : i64
    %seven = arith.constant 7 : i64
    %e1 = tensor.empty(%n) : tensor<?xi64>
    %r1 = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e1) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %s = arith.remui %x, %c41 : i64
      %y = arith.shrui %x, %s : i64
      %a1 = tensor.insert %y into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %e2 = tensor.empty(%n) : tensor<?xi64>
    %r2 = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e2) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %p = arith.addi %x, %below : i64
      %d = arith.subi %zero, %x : i64
      %y = arith.remsi %p, %d : i64
      %a1 = tensor.insert %y into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %e3 = tensor.empty(%n) : tensor<?xi64>
    %r3 = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e3) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %p = arith.subi %x, %two : i64
      %y = arith.remui %p, %seven : i64
      %a1 = tensor.insert %y into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    return %r1, %r2, %r3 : tensor<?xi64>, tensor<?xi64>, tensor<?xi64>
  }
  idr.func @ones(%n: index) -> tensor<?xf64> attributes {total, no_inline} {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %one = arith.constant 1.0 : f64
    %e = tensor.empty(%n) : tensor<?xf64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xf64>) {
      %a1 = tensor.insert %one into %a[%i] : tensor<?xf64>
      scf.yield %a1 : tensor<?xf64>
    }
    return %r : tensor<?xf64>
  }
  idr.func @rows(%n: index, %v: tensor<?xf64>) -> tensor<?xf64> attributes {total, no_inline} {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %zero = arith.constant 0.0 : f64
    %zeroi = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %unit = arith.constant 1.0 : f64
    %m = tensor.dim %v, %c0 : tensor<?xf64>
    %e = tensor.empty(%n) : tensor<?xf64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xf64>) {
      %ii = arith.index_cast %i : index to i64
      %i1 = arith.addi %ii, %one : i64
      %s = scf.for %j = %c0 to %m step %c1 iter_args(%acc = %zero) -> (f64) {
        %x = tensor.extract %v[%j] : tensor<?xf64>
        %jj = arith.index_cast %j : index to i64
        %ij = arith.addi %ii, %jj : i64
        %ij1 = arith.addi %ij, %one : i64
        %p = arith.muli %ij, %ij1 : i64
        %q = arith.divsi %p, %two : i64
        %rem = arith.remsi %p, %two : i64
        %neg = arith.cmpi slt, %rem, %zeroi : i64
        %down = arith.subi %q, %one : i64
        %h = arith.select %neg, %down, %q : i64
        %k = arith.addi %h, %i1 : i64
        %d = arith.sitofp %k : i64 to f64
        %f = arith.divf %unit, %d : f64
        %g = arith.mulf %f, %x : f64
        %t = arith.addf %acc, %g : f64
        scf.yield %t : f64
      }
      %a1 = tensor.insert %s into %a[%i] : tensor<?xf64>
      scf.yield %a1 : tensor<?xf64>
    }
    return %r : tensor<?xf64>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %b, %w1 = idr.io.get_byte %w
    %b64 = arith.extui %b : i32 to i64
    %n = arith.index_cast %b64 : i64 to index
    %sq = idr.call @squares(%n) : (index) -> tensor<?xi64>
    %e8 = idr.call @eighth(%n) : (index) -> tensor<?xi64>
    %x:3 = idr.call @inexact(%n) : (index) -> (tensor<?xi64>, tensor<?xi64>, tensor<?xi64>)
    %v = idr.call @ones(%n) : (index) -> tensor<?xf64>
    %r = idr.call @rows(%n, %v) : (index, tensor<?xf64>) -> tensor<?xf64>
    %s0 = tensor.extract %sq[%c0] : tensor<?xi64>
    %w2 = idr.io.put_sint %s0, %w1 : i64
    %s1 = tensor.extract %e8[%c0] : tensor<?xi64>
    %w3 = idr.io.put_sint %s1, %w2 : i64
    %s2 = tensor.extract %x#0[%c0] : tensor<?xi64>
    %w4 = idr.io.put_sint %s2, %w3 : i64
    %s3 = tensor.extract %x#1[%c0] : tensor<?xi64>
    %w5 = idr.io.put_sint %s3, %w4 : i64
    %s4 = tensor.extract %x#2[%c0] : tensor<?xi64>
    %w6 = idr.io.put_sint %s4, %w5 : i64
    %r0 = tensor.extract %r[%c0] : tensor<?xf64>
    %w7 = idr.io.put_double %r0, %w6
    return %w7 : !idr.world
  }
}
