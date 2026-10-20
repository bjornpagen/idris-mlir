// RUN: rm -rf %t.d && mkdir -p %t.d
// RUN: idris-mlir -c %s -o %t.o --mlir-disable-threading -mlir-print-ir-module-scope -mlir-print-ir-after-all -mlir-print-ir-tree-dir=%t.d
// RUN: %cc %t.o -o %t
// RUN: printf '\000' | %t | FileCheck %s --check-prefix=ONE
// RUN: printf '\006' | %t | FileCheck %s --check-prefix=SEVEN
// RUN: printf '\377' | %t | FileCheck %s --check-prefix=ALL
// RUN: sh -c 'cp %t.d/builtin_module_no-symbol-name/func_func_squares/*_transform-interpreter.mlir %t.squares.mlir && cp %t.d/builtin_module_no-symbol-name/func_func_rows/*_transform-interpreter.mlir %t.rows.mlir && cp %t.d/builtin_module_no-symbol-name/func_func_sumf/*_transform-interpreter.mlir %t.sumf.mlir'
// RUN: sh -c 'for f in squares rows sumf; do idris-mlir-opt %t.$f.mlir --transform-interpreter=entry-point=idr.vectorization.cleanup -o /dev/null || exit 1; done'
// RUN: idris-mlir-opt %t.squares.mlir --idr-expect=holds=vectorized=@squares -o /dev/null
// RUN: idris-mlir-opt %t.rows.mlir --idr-expect=holds=vectorized=@rows -o /dev/null
// A loop over an array with a parallel dimension computes on the target's
// lanes after the vectorization schedule, as many as the target entry's
// CPU's vector registers hold; vectorized reads no lane count, so the test
// runs on the host's target. Each function keeps its own body (no_inline),
// so its loops are read where they were written, in the module printed
// after the schedule ran on it. A tabulation's tile loop steps by the lanes
// and writes vectors. A float fold over each row keeps its combine in
// index order: the rows are the lanes, each adding its row in order, so no
// reduction across lanes is anywhere. A lone float fold is a loop in index
// order and computes on no vector, so its result is the same on every
// target. The schedule library's unit-dimension cleanup, run again with
// its failure not suppressed on what the schedule left, converges.
// The program makes arrays of 1 to 256 elements, as the input byte says,
// and prints the first and the last of the squares and of the row sums and
// the lone sum, each fold's in index order, as IEEE doubles added in index
// order give them: one element, seven (no whole number of lanes on any
// target) and 256.
// ONE: {{^}}001.01.01.0{{$}}
// SEVEN: {{^}}0362.59285714285714250.73013375513375527.0{{$}}
// ALL: {{^}}0650256.1243449628172810.694124696732443256.0{{$}}
idr.program @rows root(@root) stage(higher) types #idr.types<> {
  idr.func @squares(%n: index) -> tensor<?xi64> attributes {total, no_inline} {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      %x = arith.index_cast %i : index to i64
      %sq = arith.muli %x, %x : i64
      idr.array.yield %sq : i64
    } : tensor<?xi64>
    return %t : tensor<?xi64>
  }
  idr.func @ones(%n: index) -> tensor<?xf64> attributes {total, no_inline} {
    %t = idr.tabulate [%n] {
    ^bb0(%i: index):
      %one = arith.constant 1.0 : f64
      idr.array.yield %one : f64
    } : tensor<?xf64>
    return %t : tensor<?xf64>
  }
  // Row i is the sum over j of v[j] / (i + 1 + j), added in order of j.
  idr.func @rows(%n: index, %v: tensor<?xf64>) -> tensor<?xf64> attributes {total, no_inline} {
    %c0 = arith.constant 0 : index
    %m = tensor.dim %v, %c0 : tensor<?xf64>
    %zeros = idr.tabulate [%n] {
    ^bb0(%i: index):
      %zero = arith.constant 0.0 : f64
      idr.array.yield %zero : f64
    } : tensor<?xf64>
    %r = idr.fold_last %zeros [%m] {
    ^bb0(%i: index, %j: index, %acc: f64):
      %one = arith.constant 1 : i64
      %ii = arith.index_cast %i : index to i64
      %i1 = arith.addi %ii, %one : i64
      %x = tensor.extract %v[%j] : tensor<?xf64>
      %jj = arith.index_cast %j : index to i64
      %ij = arith.addi %i1, %jj : i64
      %d = arith.sitofp %ij : i64 to f64
      %q = arith.divf %x, %d : f64
      %t = arith.addf %acc, %q : f64
      idr.array.yield %t : f64
    } : tensor<?xf64> -> tensor<?xf64>
    return %r : tensor<?xf64>
  }
  idr.func @sumf(%v: tensor<?xf64>) -> f64 attributes {total, no_inline} {
    %c0 = arith.constant 0 : index
    %zero = arith.constant 0.0 : f64
    %m = tensor.dim %v, %c0 : tensor<?xf64>
    %z = tensor.from_elements %zero : tensor<f64>
    %s = idr.fold_last %z [%m] {
    ^bb0(%j: index, %acc: f64):
      %x = tensor.extract %v[%j] : tensor<?xf64>
      %t = arith.addf %acc, %x : f64
      idr.array.yield %t : f64
    } : tensor<f64> -> tensor<f64>
    %r = tensor.extract %s[] : tensor<f64>
    return %r : f64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %b, %w1 = idr.io.get_byte %w
    %b64 = arith.extui %b : i32 to i64
    %bi = arith.index_cast %b64 : i64 to index
    %n = arith.addi %bi, %c1 : index
    %sq = idr.call @squares(%n) : (index) -> tensor<?xi64>
    %s0 = tensor.extract %sq[%c0] : tensor<?xi64>
    %sl = tensor.extract %sq[%bi] : tensor<?xi64>
    %w2 = idr.io.put_sint %s0, %w1 : i64
    %ws = idr.io.put_sint %sl, %w2 : i64
    %v = idr.call @ones(%n) : (index) -> tensor<?xf64>
    %r = idr.call @rows(%n, %v) : (index, tensor<?xf64>) -> tensor<?xf64>
    %r0 = tensor.extract %r[%c0] : tensor<?xf64>
    %rl = tensor.extract %r[%bi] : tensor<?xf64>
    %w3 = idr.io.put_double %r0, %ws
    %wr = idr.io.put_double %rl, %w3
    %t = idr.call @sumf(%v) : (tensor<?xf64>) -> f64
    %w4 = idr.io.put_double %t, %wr
    return %w4 : !idr.world
  }
}
