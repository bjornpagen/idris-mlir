// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=dims-known=@of_size,returns=@of_size:_,returns=@of_constant:5,returns=@of_negative:0,returns=@of_argument:_,dims-known=@folded -o /dev/null
// RUN: sed 's/idr.call @folded(/idr.call @at_run_time(/' %s > %t.run.mlir
// RUN: %differential %t.run.mlir %s
// RUN: sed 's/%n = arith.constant 1000 : i64/%n = arith.constant 999 : i64/' %s > %t.wrong.mlir
// RUN: not %differential %t.run.mlir %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// The dimension of a new array is the size it was made with, clamped at 0
// (a negative size makes an empty array): memref.dim of idr.array.new
// folds, as upstream folds the dimension of memref.alloc, so a program's
// own test of the size meets the value the bounds check compares against.
//
// The extent of the array as made at run time is the oracle for every row:
// each row's extent folds in its own region (@folded, where no extent is
// asked of an array the row made), and is asked at run time of the array
// the row the byte read chose made (@at_run_time, which the sed makes the
// program's, and which returns the array too, so that the extent is not
// its one use, which would move into the rows). On the byte of each row,
// and on the empty input for the last, the two print the same: the size,
// then the extent. The rows: sizes of 0, 1 and 2, a few and a thousand,
// and negative ones down to -2^62 and the most negative Int, which make
// empty arrays. A wrong fold is found on its row: the sed makes row 6's
// size 999, where the run makes 1000.
// WRONG: differential: {{.*}}run.mlir and {{.*}}wrong.mlir differ on '\0006'
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN: \0005
// STDIN: \0006
// STDIN: \0007
// STDIN: \0010
// STDIN:
idr.program @"array-dim" root(@Prog.main) stage(first) {
  // A size the program computes: the dimension is that size at least 0, and
  // no memref.dim is left.
  idr.func @of_size(%n: i64, %w: !idr.world) -> i64 {
    %fill = arith.constant 7 : i64
    %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len : i64
  }

  // A constant size: the dimension is a constant.
  idr.func @of_constant(%w: !idr.world) -> i64 {
    %n = arith.constant 5 : i64
    %fill = arith.constant 7 : i64
    %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len : i64
  }

  // A negative constant size: an empty array.
  idr.func @of_negative(%w: !idr.world) -> i64 {
    %n = arith.constant -3 : i64
    %fill = arith.constant 7 : i64
    %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len : i64
  }

  // An array from elsewhere has a dimension nothing here knows: the read
  // stays for the lowering.
  idr.func @of_argument(%a: memref<?xi64, #idr.world>) -> i64 {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %len : i64
  }
  // The size of each row, the last the default one, and an array made with
  // it: the array the byte read chose, whose extent is known only at run time.
  idr.func @rows(%row: i64, %w: !idr.world) -> (i64, memref<?xi64, #idr.world>, !idr.world) {
    %r:3 = idr.match_lit %row : i64 -> (i64, memref<?xi64, #idr.world>, !idr.world) {
    case 0 {
      %n = arith.constant -3 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      idr.yield %n, %a, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 1 {
      %n = arith.constant -1 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      idr.yield %n, %a, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 2 {
      %n = arith.constant 0 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      idr.yield %n, %a, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 3 {
      %n = arith.constant 1 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      idr.yield %n, %a, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 4 {
      %n = arith.constant 2 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      idr.yield %n, %a, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 5 {
      %n = arith.constant 5 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      idr.yield %n, %a, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 6 {
      %n = arith.constant 1000 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      idr.yield %n, %a, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 7 {
      %n = arith.constant -9223372036854775808 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      idr.yield %n, %a, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 8 {
      %n = arith.constant -4611686018427387904 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      idr.yield %n, %a, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
    }
    default(%other: i64) {
      %n = arith.constant 7 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      idr.yield %n, %a, %w1 : i64, memref<?xi64, #idr.world>, !idr.world
    }
    }
    return %r#0, %r#1, %r#2 : i64, memref<?xi64, #idr.world>, !idr.world
  }
  // The extent of the array the row made, asked at run time. The array is
  // returned too, so that the extent is not its one use, which would move
  // into the rows.
  idr.func @at_run_time(%row: i64, %w: !idr.world) -> (i64, i64, memref<?xi64, #idr.world>, !idr.world) {
    %n, %a, %w1 = idr.call @rows(%row, %w) : (i64, !idr.world) -> (i64, memref<?xi64, #idr.world>, !idr.world)
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %len = arith.index_cast %d : index to i64
    return %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
  }
  // The extent of each row's array, which folds to its size at least 0.
  idr.func @folded(%row: i64, %w: !idr.world) -> (i64, i64, memref<?xi64, #idr.world>, !idr.world) {
    %r:4 = idr.match_lit %row : i64 -> (i64, i64, memref<?xi64, #idr.world>, !idr.world) {
    case 0 {
      %n = arith.constant -3 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      %c0 = arith.constant 0 : index
      %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
      %len = arith.index_cast %d : index to i64
      idr.yield %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 1 {
      %n = arith.constant -1 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      %c0 = arith.constant 0 : index
      %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
      %len = arith.index_cast %d : index to i64
      idr.yield %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 2 {
      %n = arith.constant 0 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      %c0 = arith.constant 0 : index
      %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
      %len = arith.index_cast %d : index to i64
      idr.yield %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 3 {
      %n = arith.constant 1 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      %c0 = arith.constant 0 : index
      %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
      %len = arith.index_cast %d : index to i64
      idr.yield %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 4 {
      %n = arith.constant 2 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      %c0 = arith.constant 0 : index
      %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
      %len = arith.index_cast %d : index to i64
      idr.yield %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 5 {
      %n = arith.constant 5 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      %c0 = arith.constant 0 : index
      %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
      %len = arith.index_cast %d : index to i64
      idr.yield %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 6 {
      %n = arith.constant 1000 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      %c0 = arith.constant 0 : index
      %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
      %len = arith.index_cast %d : index to i64
      idr.yield %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 7 {
      %n = arith.constant -9223372036854775808 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      %c0 = arith.constant 0 : index
      %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
      %len = arith.index_cast %d : index to i64
      idr.yield %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
    }
    case 8 {
      %n = arith.constant -4611686018427387904 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      %c0 = arith.constant 0 : index
      %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
      %len = arith.index_cast %d : index to i64
      idr.yield %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
    }
    default(%other: i64) {
      %n = arith.constant 7 : i64
      %fill = arith.constant 7 : i64
      %a, %w1 = idr.array.new [%n], %fill, %w : i64 -> memref<?xi64, #idr.world>
      %c0 = arith.constant 0 : index
      %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
      %len = arith.index_cast %d : index to i64
      idr.yield %n, %len, %a, %w1 : i64, i64, memref<?xi64, #idr.world>, !idr.world
    }
    }
    return %r#0, %r#1, %r#2, %r#3 : i64, i64, memref<?xi64, #idr.world>, !idr.world
  }
  // The program: the size and the extent of the row the byte read chooses,
  // folded, or, in the run form, asked at run time.
  idr.func @Prog.main(%w0: !idr.world) -> !idr.world {
    %byte, %w1 = idr.io.get_byte %w0
    %row = arith.extui %byte : i32 to i64
    %n, %len, %a, %w2 = idr.call @folded(%row, %w1) : (i64, !idr.world) -> (i64, i64, memref<?xi64, #idr.world>, !idr.world)
    %space = arith.constant 32 : i32
    %newline = arith.constant 10 : i32
    %w3 = idr.io.put_sint %n, %w2 : i64
    %w4 = idr.io.put_char %space, %w3
    %w5 = idr.io.put_sint %len, %w4 : i64
    %w6 = idr.io.put_char %newline, %w5
    return %w6 : !idr.world
  }
}
