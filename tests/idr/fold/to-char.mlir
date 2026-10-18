// NEEDS-ACCEPTANCE: idr.to_char_s and idr.to_char_u fold to the same characters as the flagged op did.
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@chars:955/0/0/200 -o /dev/null
idr.program @"to-char" root(@root) stage(first) {
  idr.func @chars() -> (i32, i32, i32, i32) {
    %a = arith.constant 955 : i64
    %b = arith.constant 55296 : i64
    %c = arith.constant -5 : i64
    %d = arith.constant 200 : i8
    %ra = idr.to_char_s %a : i64
    %rb = idr.to_char_s %b : i64
    %rc = idr.to_char_s %c : i64
    %rd = idr.to_char_u %d : i8
    return %ra, %rb, %rc, %rd : i32, i32, i32, i32
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
