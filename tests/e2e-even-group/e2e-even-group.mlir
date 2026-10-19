// RUN: awk '/^!Many = / { printf "!Many = !idr.data<\"Many\", plain ["; for (i = 0; i <= 131072; i++) { if (i > 0) printf ", "; printf "@C%d", i; if (i == 0 || i == 65536 || i == 131072) printf "(i64)"; else printf "()" } print "]>"; next } { print }' %s > %t.many.mlir
// RUN: idris-mlir -c %t.many.mlir -o %t.o
// RUN: %cc %t.o -o %t
// RUN: echo -n "abc" | %t > %t.out
// RUN: FileCheck %s < %t.out
// A sum of 131,073 constructors is three groups of tags of 16 bits: the
// group, then the tag within it. The first RUN line writes the sum where
// the line of !Many stands, C0 to C131072, with an i64 field in C0 (group
// 0), C65536 (group 1) and C131072 (group 2, the first even group past 0).
// @make builds the cell a byte read at run time names, and is never
// inlined, so the cell outlives its frame and is a heap cell; @show
// matches it, prints its constructor and field, and is its last use, so
// the cell is freed there. Each run of a group's cell is read back by its
// tags, and each is freed, so the program exits 0 after printing all
// three.
// CHECK: C0 97
// CHECK-NEXT: C65536 98
// CHECK-NEXT: C131072 99
!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!Many = !idr.data<"Many", plain [@C0(i64), @C65536(i64), @C131072(i64)]>
idr.program @"even-group" root(@Prog.main) stage(higher) {
  idr.func @make(%c: i32) -> !idr.box<!Many> attributes {total, no_inline} {
    %x = arith.extui %c : i32 to i64
    %r = idr.match_lit %c : i32 -> (!idr.box<!Many>) {
    case 97 {
      %v = idr.con !idr.box<!Many> @C0(%x : i64)
      idr.yield %v : !idr.box<!Many>
    }
    case 98 {
      %v = idr.con !idr.box<!Many> @C65536(%x : i64)
      idr.yield %v : !idr.box<!Many>
    }
    default(%d: i32) {
      %v = idr.con !idr.box<!Many> @C131072(%x : i64)
      idr.yield %v : !idr.box<!Many>
    }
    }
    return %r : !idr.box<!Many>
  }
  idr.func @show(%w: !idr.world) -> !idr.world attributes {total} {
    %c, %w1 = idr.io.get_byte %w
    %v = idr.call @make(%c) : (i32) -> !idr.box<!Many>
    %w2 = idr.match %v : !idr.box<!Many> -> (!idr.world) {
    case @C0(%a: i64) {
      %s = idr.constant !idr.str "C0 "
      %w3 = idr.io.put_str %s, %w1
      %w4 = idr.io.put_sint %a, %w3 : i64
      idr.yield %w4 : !idr.world
    }
    case @C65536(%a: i64) {
      %s = idr.constant !idr.str "C65536 "
      %w3 = idr.io.put_str %s, %w1
      %w4 = idr.io.put_sint %a, %w3 : i64
      idr.yield %w4 : !idr.world
    }
    case @C131072(%a: i64) {
      %s = idr.constant !idr.str "C131072 "
      %w3 = idr.io.put_str %s, %w1
      %w4 = idr.io.put_sint %a, %w3 : i64
      idr.yield %w4 : !idr.world
    }
    default(%d: !idr.box<!Many>) {
      %s = idr.constant !idr.str "another"
      %w3 = idr.io.put_str %s, %w1
      idr.yield %w3 : !idr.world
    }
    }
    %nl = arith.constant 10 : i32
    %w5 = idr.io.put_char %nl, %w2
    return %w5 : !idr.world
  }
  idr.func @Prog.main(%w: !idr.world) -> (!Unit, !idr.world) attributes {total} {
    %w1 = idr.call @show(%w) : (!idr.world) -> !idr.world
    %w2 = idr.call @show(%w1) : (!idr.world) -> !idr.world
    %w3 = idr.call @show(%w2) : (!idr.world) -> !idr.world
    %unit = idr.constant !Unit #idr.con<!Unit, @MkUnit, []>
    return %unit, %w3 : !Unit, !idr.world
  }
}
