// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@divfold:-4/1/-9223372036854775808/0/35/_ -o /dev/null
idr.program @division root(@root) stage(first) {
  // A division by zero is not folded: its guard crashes before it runs, and
  // the folder computes nothing a program never reaches.
  idr.func @divfold() -> (i64, i64, i64, i64, i8, i64) {
    %m7 = arith.constant -7 : i64
    %c2 = arith.constant 2 : i64
    %m2 = arith.constant -2 : i64
    %min = arith.constant -9223372036854775808 : i64
    %m1 = arith.constant -1 : i64
    %c0 = arith.constant 0 : i64
    %u250 = arith.constant 250 : i8
    %u7 = arith.constant 7 : i8
    %a = idr.div signed %m7, %c2 : i64
    %b = idr.mod signed %m7, %m2 : i64
    %c = idr.div signed %min, %m1 : i64
    %d = idr.mod signed %min, %m1 : i64
    %e = idr.div %u250, %u7 : i8
    %z = idr.div signed %c2, %c0 : i64
    return %a, %b, %c, %d, %e, %z : i64, i64, i64, i64, i8, i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
