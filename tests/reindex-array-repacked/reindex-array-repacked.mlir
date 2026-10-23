// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=owned})' -o /dev/null
// An array of positions below 5, taken where an array of positions below a
// bound no index fixes is asked, is reindexed at its element. A position
// below 5 is a word of 8 bits and one below an unknown bound is a natural,
// so the two arrays lay out apart and the reindex re-packs every element
// into a fresh array. @main tabulates three positions below 5, each its
// index, reindexes the array and passes it to @nth with a count; @nth
// reads the element at index 2 as a natural once the count is spent, and
// @main prints it. @nth recurses, so it stays a function, and the
// reindexed array, which only @nth reads, crosses a call. The module
// starts on tensors and is verified after every pass to the owned stage,
// on its tensors and then on their buffers, so it verifies, with nothing
// expected, only where the reindex is put on buffers: its operand read as
// a whole cell, its result a fresh buffer, counted and claiming its own
// cells as every re-pack into an array is, and given on at the grade its
// tensor states.
#Fin = #idr.family<"Fin" [nat] {
    @FZ <nat> where v0 + 1 ()
    @FS <nat> where v0 + 1 (!idr.self[v0])
  }>
!Below5 = !idr.data<#Fin[5]>
!BelowAny = !idr.data<#Fin[_]>
!Nat = !idr.nat<_>
!SmallNat = !idr.graded<many, static, !idr.nat<_>>
idr.program @positions root(@main) stage(first) {
  idr.func @main() {
    %none = tensor.empty() : tensor<3x!Below5>
    %xs = idr.array.tabulate outs(%none : tensor<3x!Below5>) {
    ^bb0(%i: index):
      %w = arith.index_cast %i : index to i64
      %n = idr.big.small %w : (i64) -> !SmallNat
      %x = idr.numeral.of_nat %n : !SmallNat -> !Below5
      idr.array.yield %x : !Below5
    } -> tensor<3x!Below5>
    %ys = idr.data.reindex %xs : tensor<3x!Below5> to tensor<3x!BelowAny>
    %k = arith.constant 2 : i64
    %r = idr.call @nth(%ys, %k) <{tail_kind = nontail}> : (tensor<3x!BelowAny>, i64) -> !Nat
    %b = idr.nat.to_big %r : (!Nat) -> !idr.big
    %text = idr.big.show %b : (!idr.big) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
  idr.func @nth(%xs: tensor<3x!BelowAny>, %k: i64) -> !Nat {
    %r = idr.lit.match %k : i64 -> (!Nat) {
    case 0(%key: i64) {
      %two = arith.constant 2 : index
      %x = tensor.extract %xs[%two] : tensor<3x!BelowAny>
      %n = idr.numeral.to_nat %x : !BelowAny -> !Nat
      idr.yield %n : !Nat
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %v = idr.call @nth(%xs, %j) <{tail_kind = tail}> : (tensor<3x!BelowAny>, i64) -> !Nat
      idr.yield %v : !Nat
    }
    }
    idr.return %r : !Nat
  }
}
