// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=owned},idr-expect{holds=counts-nothing=@twice})' -o /dev/null
// A string the optimizer computes and passes as static data to a function
// that would count it reaches a copy of that function keyed to static data,
// though the round of the optimizer that computed it did nothing else.
// @main appends two literals, "a" ++ "b", typed as a primitive's result
// is, at a hold its count frees, and passes the string to @twice, which
// builds a pair of it twice over, the second reference one a counted
// string takes by a dup. The string is computed from constants, so after
// the e-graph it is static data at the call, which no count frees; the
// call is keyed by the hold its argument is passed at only after the
// e-graph has run, so the round that put it there is not @main's last. At
// the owned stage, where every count is placed, no function made from
// @twice counts anything, as a copy that builds its pair of static data
// does not and @twice itself, given a counted string, would. @main hands
// each pair to @first and writes out the string it reads, so no result is
// left unread and no pair's one use is a match a copy could take in.
// @twice and @first recurse, so each stays a function wherever it is
// called, and @main calls each twice, so each returns to more than one
// place and is no join point of one caller.
!Str = !idr.graded<many, static, !idr.str>
#Pair = #idr.family<"Pair" [] {
    @MkPair (!idr.str, !idr.str)
  }>
!Pair = !idr.data<#Pair>
!MkPair = !idr.data<#Pair @MkPair>
idr.program @keyed root(@main) stage(first) {
  idr.func @main() {
    %a = idr.constant !Str "a"
    %b = idr.constant !Str "b"
    %ab = idr.str.append %a, %b : (!Str, !Str) -> !idr.str
    %line = idr.io.get_line : () -> !idr.str
    %n = idr.str.length %line : (!idr.str) -> i64
    %one = arith.constant 1 : i64
    %m = arith.addi %n, %one : i64
    %x = idr.call @twice(%ab, %n) <{tail_kind = nontail}> : (!idr.str, i64) -> !Pair
    %y = idr.call @twice(%ab, %m) <{tail_kind = nontail}> : (!idr.str, i64) -> !Pair
    %fx = idr.call @first(%x, %n) <{tail_kind = nontail}> : (!Pair, i64) -> !idr.str
    %fy = idr.call @first(%y, %m) <{tail_kind = nontail}> : (!Pair, i64) -> !idr.str
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
      %again = idr.call @twice(%s, %j) <{tail_kind = tail}> : (!idr.str, i64) -> !Pair
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
      %again = idr.call @first(%p, %j) <{tail_kind = tail}> : (!Pair, i64) -> !idr.str
      idr.yield %again : !idr.str
    }
    }
    idr.return %r : !idr.str
  } loc("first")
}
