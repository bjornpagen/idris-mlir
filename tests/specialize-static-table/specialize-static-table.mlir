// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-optimize,symbol-dce),idr-expect{holds=one-clone=@go})' -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-optimize,symbol-dce))' -o %t.mlir
// RUN: %differential %s %t.mlir
// go table i acc walks a static table from index i down to 0, the table
// the same at every step. The table is passed unchanged along the
// recursion, so the copy is keyed on it once and calls itself; the index
// changes at every step and keys nothing: one copy, not one per index.
// Each function carries the location Emit gives it, its definition's
// name, by which a copy names what it was made from.
// The differential holds the optimized program to the one as written on
// every input byte: indices past the table's end read 0, and 0 sums
// nothing.
!Table = !idr.data<"Table", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"Table">>) cons]>
idr.program @"static-table" root(@Main.main) stage(first) {
  idr.func @at(%t: !idr.box<!Table>, %i: i64) -> i64 attributes {total} {
    %r = idr.match %t : !idr.box<!Table> -> (i64) {
    case @Nil() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Cons(%h: i64, %rest: !idr.box<!Table>) {
      %v = idr.match_lit %i : i64 -> (i64) {
      case 0 {
        idr.yield %h : i64
      }
      default(%d: i64) {
        %c1 = arith.constant 1 : i64
        %j = arith.subi %i, %c1 : i64
        %w = idr.call @at(%rest, %j) : (!idr.box<!Table>, i64) -> i64
        idr.yield %w : i64
      }
      }
      idr.yield %v : i64
    }
    }
    return %r : i64
  } loc("at")
  idr.func @go(%t: !idr.box<!Table>, %i: i64, %acc: i64) -> i64 attributes {total} {
    %r = idr.match_lit %i : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %v = idr.call @at(%t, %i) : (!idr.box<!Table>, i64) -> i64
      %a = arith.addi %acc, %v : i64
      %c1 = arith.constant 1 : i64
      %j = arith.subi %i, %c1 : i64
      %s = idr.call @go(%t, %j, %a) : (!idr.box<!Table>, i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  } loc("go")
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %table = idr.constant !idr.box<!Table> #idr.con<!Table, @Cons, [3 : i64, #idr.con<!Table, @Cons, [5 : i64, #idr.con<!Table, @Cons, [7 : i64, #idr.con<!Table, @Nil, []>]>]>]>
    %c, %w1 = idr.io.get_byte %w
    %i = arith.extui %c : i32 to i64
    %zero = arith.constant 0 : i64
    %r = idr.call @go(%table, %i, %zero) : (!idr.box<!Table>, i64, i64) -> i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  } loc("Main.main")
}
