// RUN: idris-mlir-opt %s -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=higher to=owned},idr-expect{holds=counts-nothing=@twice})' -o /dev/null
// A string literal is static data, which no count frees, and @twice takes
// its string at a hold its count frees: it builds a pair of the string
// twice over, the second reference one a counted string takes by a dup.
// The frontend passes static data there as it is, so until the specializer
// has keyed each call by the hold its argument is passed at, an argument
// whose hold fits its parameter's crosses at the parameter's, and the
// module verifies as written. @main passes @twice a literal, and a static
// string a line of input chooses between two literals, which no constant
// names, so only its hold can key its call. Past the first stage each call
// reaches a copy of @twice whose parameter is static: the program verifies
// at every later stage, where a call's argument is its parameter's type
// exactly, and at the owned stage, where every count is placed, no function
// made from @twice counts anything, as a copy that builds its pair of
// static data does not and @twice itself, kept for a call passed a counted
// string, would. @main hands each pair to @first and writes out the string
// it reads, so no result of @twice is left unread for dead-result removal
// to empty it, and no pair's one use is a match a copy could take in.
// @twice and @first recurse, so each stays a function wherever it is
// called, and @main calls each twice, so each returns to more than one
// place and is no join point of one caller.
!Str = !idr.graded<many, static, !idr.str>
#Pair = #idr.family<"Pair" [] {
    @MkPair (!idr.str, !idr.str)
  }>
!Pair = !idr.data<#Pair>
!MkPair = !idr.data<#Pair @MkPair>
idr.program @keyed root(@main) stage(higher) {
  idr.func @main() {
    %c = idr.constant !Str "c"
    %line = idr.io.get_line : () -> !idr.str
    %n = idr.str.length %line : (!idr.str) -> i64
    %s = idr.lit.match %n : i64 -> (!Str) {
    case 0(%none: i64) {
      %a = idr.constant !Str "a"
      idr.yield %a : !Str
    }
    default(%some: i64) {
      %b = idr.constant !Str "b"
      idr.yield %b : !Str
    }
    }
    %x = idr.call @twice(%c, %n) : (!Str, i64) -> !Pair
    %y = idr.call @twice(%s, %n) : (!Str, i64) -> !Pair
    %fx = idr.call @first(%x, %n) : (!Pair, i64) -> !idr.str
    %fy = idr.call @first(%y, %n) : (!Pair, i64) -> !idr.str
    idr.io.put_str %fx : (!idr.str) -> ()
    idr.io.put_str %fy : (!idr.str) -> ()
    idr.return
  }
  idr.func @twice(%s: !idr.str, %k: i64) -> !Pair {
    %r = idr.lit.match %k : i64 -> (!Pair) {
    case 0(%zero: i64) {
      %p = idr.data.con(%s : !idr.str, %s : !idr.str) : !MkPair
      %q = idr.data.reindex %p : !MkPair to !Pair
      idr.yield %q : !Pair
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.call @twice(%s, %j) : (!idr.str, i64) -> !Pair
      idr.yield %again : !Pair
    }
    }
    idr.return %r : !Pair
  } loc("twice")
  idr.func @first(%p: !Pair, %k: i64) -> !idr.str {
    %r = idr.lit.match %k : i64 -> (!idr.str) {
    case 0(%zero: i64) {
      %h = idr.data.match %p : !Pair -> (!idr.str) {
      case @MkPair(%pair: !MkPair) {
        %f = idr.data.field %pair[0] : !MkPair -> !idr.str
        idr.yield %f : !idr.str
      }
      }
      idr.yield %h : !idr.str
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.call @first(%p, %j) : (!Pair, i64) -> !idr.str
      idr.yield %again : !idr.str
    }
    }
    idr.return %r : !idr.str
  } loc("first")
}
