// NEEDS-ACCEPTANCE: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before.
// RUN: rm -rf %t.d && mkdir -p %t.d
// RUN: idris-mlir -c %s -o %t.o --mlir-disable-threading -mlir-print-ir-module-scope -mlir-print-ir-after-all -mlir-print-ir-tree-dir=%t.d
// RUN: sh -c 'cp %t.d/builtin_module_no-symbol-name/func_func_squares/*_transform-interpreter.mlir %t.squares.mlir && cp %t.d/builtin_module_no-symbol-name/func_func_rows/*_transform-interpreter.mlir %t.rows.mlir && cp %t.d/builtin_module_no-symbol-name/func_func_sumf/*_transform-interpreter.mlir %t.sumf.mlir'
// RUN: sh -c 'for f in squares rows sumf; do idris-mlir-opt %t.$f.mlir --transform-interpreter=entry-point=idr.vectorization.cleanup -o /dev/null || exit 1; done'
// RUN: idris-mlir-opt %t.squares.mlir --idr-expect=holds=vectorized=@squares -o /dev/null
// RUN: idris-mlir-opt %t.rows.mlir --idr-expect=holds=vectorized=@rows -o /dev/null
// NEEDS-ACCEPTANCE: the tree printer's file names for a function (func_func_<symbol>/<n>_<m>_<pass>.mlir).
// NEEDS-ACCEPTANCE: that the schedule library's unit-dimension cleanup (@idr.vectorization.cleanup), run again on what the schedule left with its failure not suppressed, converges within its budget on every function here.
// The arm64 counterpart of rows-x86-64: the same loops on the arm64 target
// entry's CPU (apple-m1), whose vector register is one 128-bit NEON
// register, so a loop of 64-bit words steps by two lanes. A float fold
// over each row still adds each lane's row in index order, and a lone
// float fold computes on no vector.
idr.program @"rows-aarch64" root(@root) stage(higher) {
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
    %one = arith.constant 1 : i64
    %m = tensor.dim %v, %c0 : tensor<?xf64>
    %e = tensor.empty(%n) : tensor<?xf64>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xf64>) {
      %ii = arith.index_cast %i : index to i64
      %i1 = arith.addi %ii, %one : i64
      %s = scf.for %j = %c0 to %m step %c1 iter_args(%acc = %zero) -> (f64) {
        %x = tensor.extract %v[%j] : tensor<?xf64>
        %jj = arith.index_cast %j : index to i64
        %ij = arith.addi %i1, %jj : i64
        %d = arith.sitofp %ij : i64 to f64
        %q = arith.divf %x, %d : f64
        %t = arith.addf %acc, %q : f64
        scf.yield %t : f64
      }
      %a1 = tensor.insert %s into %a[%i] : tensor<?xf64>
      scf.yield %a1 : tensor<?xf64>
    }
    return %r : tensor<?xf64>
  }
  idr.func @sumf(%v: tensor<?xf64>) -> f64 attributes {total, no_inline} {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %zero = arith.constant 0.0 : f64
    %m = tensor.dim %v, %c0 : tensor<?xf64>
    %s = scf.for %j = %c0 to %m step %c1 iter_args(%acc = %zero) -> (f64) {
      %x = tensor.extract %v[%j] : tensor<?xf64>
      %t = arith.addf %acc, %x : f64
      scf.yield %t : f64
    }
    return %s : f64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %b, %w1 = idr.io.get_byte %w
    %b64 = arith.extui %b : i32 to i64
    %n = arith.index_cast %b64 : i64 to index
    %sq = idr.call @squares(%n) : (index) -> tensor<?xi64>
    %s0 = tensor.extract %sq[%c0] : tensor<?xi64>
    %w2 = idr.io.put_sint %s0, %w1 : i64
    %v = idr.call @ones(%n) : (index) -> tensor<?xf64>
    %r = idr.call @rows(%n, %v) : (index, tensor<?xf64>) -> tensor<?xf64>
    %r0 = tensor.extract %r[%c0] : tensor<?xf64>
    %w3 = idr.io.put_double %r0, %w2
    %t = idr.call @sumf(%v) : (tensor<?xf64>) -> f64
    %w4 = idr.io.put_double %t, %w3
    return %w4 : !idr.world
  }
}
