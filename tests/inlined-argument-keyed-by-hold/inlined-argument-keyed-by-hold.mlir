// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=owned},idr-expect{holds=counts-nothing=@twice})' -o /dev/null
// A string that only inlining lets the e-graph compute, passed as static
// data to a function that would count it, reaches a copy of that function
// keyed to static data, though no round of the optimizer saw it computed.
// @main passes the literal "a" to @wrap, which appends the literal "b" to
// what it is given and passes the result to @twice, which builds a pair of
// it twice over, the second reference one a counted string takes by a dup.
// The two literals stand in two functions, so no e-graph of the optimizer's
// computes "ab": @wrap's own knows nothing of what it is given, and @main's
// reads nothing of @wrap's body, which calls @twice and so is no leaf.
// @wrap stands on no cycle and its calls are few, so the inlining after the
// optimizer copies it into @main, and the simplification that follows
// computes "ab" there, static data at @twice's argument, which no count
// frees. At the owned stage, where every count is placed, no function made
// from @twice counts anything, as a copy that builds its pair of static
// data does not and @twice itself, given a counted string, would. @main
// hands each pair to @first and writes out the string it reads, so no
// result is left unread and no pair's one use is a match a copy could take
// in. @twice and @first recurse, so each stays a function wherever it is
// called, and @main calls each twice, so each returns to more than one place
// and is no join point of one caller; so does @wrap, until it is inlined.
!Str = !idr.graded<many, static, !idr.str>
#Pair = #idr.family<"Pair" [] {
    @MkPair (!idr.str, !idr.str)
  }>
!Pair = !idr.data<#Pair>
!MkPair = !idr.data<#Pair @MkPair>
idr.program @inlined root(@main) stage(first) {
  idr.func @main() {
    %a = idr.constant !Str "a"
    %line = idr.io.get_line : () -> !idr.str
    %n = idr.str.length %line : (!idr.str) -> i64
    %one = arith.constant 1 : i64
    %m = arith.addi %n, %one : i64
    %x = idr.call @wrap(%a, %n) <{tail_kind = nontail}> : (!Str, i64) -> !Pair
    %y = idr.call @wrap(%a, %m) <{tail_kind = nontail}> : (!Str, i64) -> !Pair
    %fx = idr.call @first(%x, %n) <{tail_kind = nontail}> : (!Pair, i64) -> !idr.str
    %fy = idr.call @first(%y, %m) <{tail_kind = nontail}> : (!Pair, i64) -> !idr.str
    idr.io.put_str %fx : (!idr.str) -> ()
    idr.io.put_str %fy : (!idr.str) -> ()
    idr.return
  }
  idr.func @wrap(%s: !idr.str, %k: i64) -> !Pair {
    %b = idr.constant !Str "b"
    %sb = idr.str.append %s, %b : (!idr.str, !Str) -> !idr.str
    %p = idr.call @twice(%sb, %k) <{tail_kind = tail}> : (!idr.str, i64) -> !Pair
    idr.return %p : !Pair
  } loc("wrap")
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
