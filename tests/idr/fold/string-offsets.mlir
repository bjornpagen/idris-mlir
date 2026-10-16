// RUN: idris-mlir-opt %s --mlir-disable-threading --canonicalize '--idr-expect=holds=folds-balanced,returns=@offsets:104/104/233/233/0/0/128512/"h\C3\A9llo"/"\C3\A9llo"/"llo"/""/""/"\F0\9F\98\80b"' -o /dev/null
// NEEDS-ACCEPTANCE: the op of the offset after a character is gone; the other folds and their values are unchanged.
// A string read by byte offset folds at every constant offset, since each
// offset has a meaning: below 0 is the start, past the end is the end, and
// an offset inside a character's encoding stands for that character's
// start. At the end there is no character (0), and nothing is left.
// Dropping no bytes gives the string itself and every
// byte the empty string, each with a reference the folder releases.
// "h\C3\A9llo" is h, U+00E9 in two bytes and llo; "a\F0\9F\98\80b" is a,
// U+1F600 in four bytes and b.
idr.program @"string-offsets" root(@root) stage(first) {
  idr.func @offsets() -> (i32, i32, i32, i32, i32, i32, i32,
                           !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str) {
    %s = idr.constant "h\C3\A9llo" : !idr.str
    %t = idr.constant "a\F0\9F\98\80b" : !idr.str
    %m4 = arith.constant -4 : i64
    %m3 = arith.constant -3 : i64
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %c3 = arith.constant 3 : i64
    %c4 = arith.constant 4 : i64
    %c6 = arith.constant 6 : i64
    %c99 = arith.constant 99 : i64
    %c100 = arith.constant 100 : i64
    %a0 = idr.str.scalar_at %s, %m3
    %a1 = idr.str.scalar_at %s, %c0
    %a2 = idr.str.scalar_at %s, %c1
    %a3 = idr.str.scalar_at %s, %c2
    %a4 = idr.str.scalar_at %s, %c6
    %a5 = idr.str.scalar_at %s, %c100
    %a6 = idr.str.scalar_at %t, %c3
    %d0 = idr.str.drop_bytes %s, %m4
    %d1 = idr.str.drop_bytes %s, %c2
    %d2 = idr.str.drop_bytes %s, %c3
    %d3 = idr.str.drop_bytes %s, %c6
    %d4 = idr.str.drop_bytes %s, %c99
    %d5 = idr.str.drop_bytes %t, %c4
    return %a0, %a1, %a2, %a3, %a4, %a5, %a6,
           %d0, %d1, %d2, %d3, %d4, %d5
        : i32, i32, i32, i32, i32, i32, i32,
          !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
