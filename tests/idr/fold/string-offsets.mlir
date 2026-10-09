// RUN: idris-mlir-opt %s --mlir-disable-threading --canonicalize --idr-expect=holds=folds-balanced > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A string read by byte offset folds at every constant offset, since each
// offset has a meaning: below 0 is the start, past the end is the end, and
// an offset inside a character's encoding stands for that character's
// start. At the end there is no character (0), the next offset is the end,
// and nothing is left. Dropping no bytes gives the string itself and every
// byte the empty string, each with a reference the folder releases.
// "h\C3\A9llo" is h, U+00E9 in two bytes and llo; "a\F0\9F\98\80b" is a,
// U+1F600 in four bytes and b.
// CHECK-LABEL: func.func @offsets(
// CHECK-DAG: %[[H:.*]] = arith.constant 104 : i32
// CHECK-DAG: %[[ACUTE:.*]] = arith.constant 233 : i32
// CHECK-DAG: %[[NONE:.*]] = arith.constant 0 : i32
// CHECK-DAG: %[[EMOJI:.*]] = arith.constant 128512 : i32
// CHECK-DAG: %[[AT1:.*]] = arith.constant 1 : i64
// CHECK-DAG: %[[AT3:.*]] = arith.constant 3 : i64
// CHECK-DAG: %[[AT5:.*]] = arith.constant 5 : i64
// CHECK-DAG: %[[AT6:.*]] = arith.constant 6 : i64
// CHECK-DAG: %[[ALL:.*]] = idr.constant "h\C3\A9llo" : !idr.str
// CHECK-DAG: %[[FROM1:.*]] = idr.constant "\C3\A9llo" : !idr.str
// CHECK-DAG: %[[FROM3:.*]] = idr.constant "llo" : !idr.str
// CHECK-DAG: %[[EMPTY:.*]] = idr.constant "" : !idr.str
// CHECK-DAG: %[[SMILE:.*]] = idr.constant "\F0\9F\98\80b" : !idr.str
// CHECK-NOT: idr.str.scalar_at
// CHECK-NOT: idr.str.scalar_end
// CHECK-NOT: idr.str.drop_bytes
// CHECK: return %[[H]], %[[H]], %[[ACUTE]], %[[ACUTE]], %[[NONE]], %[[NONE]], %[[EMOJI]], %[[AT1]], %[[AT1]], %[[AT3]], %[[AT3]], %[[AT6]], %[[AT6]], %[[AT6]], %[[AT5]], %[[ALL]], %[[FROM1]], %[[FROM3]], %[[EMPTY]], %[[EMPTY]], %[[SMILE]] :
func.func @offsets() -> (i32, i32, i32, i32, i32, i32, i32,
                         i64, i64, i64, i64, i64, i64, i64, i64,
                         !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str) {
  %s = idr.constant "h\C3\A9llo" : !idr.str
  %t = idr.constant "a\F0\9F\98\80b" : !idr.str
  %m4 = arith.constant -4 : i64
  %m3 = arith.constant -3 : i64
  %m1 = arith.constant -1 : i64
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
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
  %e0 = idr.str.scalar_end %s, %m1
  %e1 = idr.str.scalar_end %s, %c0
  %e2 = idr.str.scalar_end %s, %c1
  %e3 = idr.str.scalar_end %s, %c2
  %e4 = idr.str.scalar_end %s, %c5
  %e5 = idr.str.scalar_end %s, %c6
  %e6 = idr.str.scalar_end %s, %c100
  %e7 = idr.str.scalar_end %t, %c1
  %d0 = idr.str.drop_bytes %s, %m4
  %d1 = idr.str.drop_bytes %s, %c2
  %d2 = idr.str.drop_bytes %s, %c3
  %d3 = idr.str.drop_bytes %s, %c6
  %d4 = idr.str.drop_bytes %s, %c99
  %d5 = idr.str.drop_bytes %t, %c4
  return %a0, %a1, %a2, %a3, %a4, %a5, %a6, %e0, %e1, %e2, %e3, %e4, %e5, %e6, %e7,
         %d0, %d1, %d2, %d3, %d4, %d5
      : i32, i32, i32, i32, i32, i32, i32, i64, i64, i64, i64, i64, i64, i64, i64,
        !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str
}
