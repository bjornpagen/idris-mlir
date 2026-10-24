// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=tail-calls=@f:@g,results-as-given=@f:@g,tail-calls=@h:@g,tail-calls=@c:@u,results-as-given=@c:@u})' -o /dev/null
// A tail call whose callee returns an array whose elements are laid out
// otherwise than its caller's is made a tail call as a data result is,
// through the array's element. A position below 5 is a word of 8 bits and
// one below a bound no index fixes is a natural, so an array of the one
// and an array of the other lay out apart, and a reindex between them
// re-packs every element.
// @f returns positions below an unknown bound; where its count is spent it
// tail-calls @g, which returns positions below 5, so as written a re-pack
// follows the call and it is no tail call. The copy of @g it calls
// instead returns its array with each element marked open, still below 5
// and laid out as @f's are: the cast after the call builds nothing, and
// the call is a tail call that gives its result as its callee returns it.
// @h makes the same call of @g at another count, so the copy of @g
// returns to more than one place and is never a join point of its one
// tail caller.
// The other way round, @c returns positions below 5 and tail-calls @u,
// which returns positions below an unknown bound, cast to 5 after it. No
// copy of @u could give its positions below 5 laid out as words, since no
// index says @u's are, so @c's own result is laid out open, each element
// still below 5: its tail call gives its result as @u returns it, and its
// callers pay the re-pack after their call.
// The module verifies after every pass to the graded stage, where every
// tail call's result is laid out as its caller returns it. Each function
// recurses, so each stays a function wherever another is inlined into it,
// and @main calls each where no tail is lost, so none becomes a join point
// of its one tail caller. @main prints an element of what @f and @c give,
// so neither result is left unread.
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
    %tab = idr.array.tabulate outs(%none : tensor<3x!Below5>) {
    ^bb0(%i: index):
      %w = arith.index_cast %i : index to i64
      %n = idr.big.small %w : (i64) -> !SmallNat
      %x = idr.numeral.of_nat %n : !SmallNat -> !Below5
      idr.array.yield %x : !Below5
    } -> tensor<3x!Below5>
    %xs = tensor.cast %tab : tensor<3x!Below5> to tensor<?x!Below5>
    %ys = idr.data.reindex %xs : tensor<?x!Below5> to tensor<?x!BelowAny>
    %three = arith.constant 3 : i64
    %five = arith.constant 5 : i64
    %zero = arith.constant 0 : index
    %a = idr.call @f(%xs, %three) : (tensor<?x!Below5>, i64) -> tensor<?x!BelowAny>
    %b = idr.call @f(%xs, %five) : (tensor<?x!Below5>, i64) -> tensor<?x!BelowAny>
    %c = idr.call @h(%xs, %three) : (tensor<?x!Below5>, i64) -> tensor<?x!BelowAny>
    %d = idr.call @h(%xs, %five) : (tensor<?x!Below5>, i64) -> tensor<?x!BelowAny>
    %e = idr.call @c(%ys, %three) : (tensor<?x!BelowAny>, i64) -> tensor<?x!Below5>
    %g = idr.call @c(%ys, %five) : (tensor<?x!BelowAny>, i64) -> tensor<?x!Below5>
    %u = idr.call @u(%ys, %three) : (tensor<?x!BelowAny>, i64) -> tensor<?x!BelowAny>
    %v = idr.call @u(%ys, %five) : (tensor<?x!BelowAny>, i64) -> tensor<?x!BelowAny>
    %fa = tensor.extract %a[%zero] : tensor<?x!BelowAny>
    %fn = idr.numeral.to_nat %fa : !BelowAny -> !Nat
    %fb = idr.nat.to_big %fn : (!Nat) -> !idr.big
    %ft = idr.big.show %fb : (!idr.big) -> !idr.str
    idr.io.put_str %ft : (!idr.str) -> ()
    %ce = tensor.extract %e[%zero] : tensor<?x!Below5>
    %cn = idr.numeral.to_nat %ce : !Below5 -> !Nat
    %cb = idr.nat.to_big %cn : (!Nat) -> !idr.big
    %ct = idr.big.show %cb : (!idr.big) -> !idr.str
    idr.io.put_str %ct : (!idr.str) -> ()
    idr.return
  }
  idr.func @f(%xs: tensor<?x!Below5>, %n: i64) -> tensor<?x!BelowAny> {
    %r = idr.lit.match %n : i64 -> (tensor<?x!BelowAny>) {
    case 0(%key0: i64) {
      %v = idr.call @g(%xs, %n) : (tensor<?x!Below5>, i64) -> tensor<?x!Below5>
      %w = idr.data.reindex %v : tensor<?x!Below5> to tensor<?x!BelowAny>
      idr.yield %w : tensor<?x!BelowAny>
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %d, %one : i64
      %v = idr.tail_call @f(%xs, %m) : (tensor<?x!Below5>, i64) -> tensor<?x!BelowAny>
      idr.yield %v : tensor<?x!BelowAny>
    }
    }
    idr.return %r : tensor<?x!BelowAny>
  } loc("f")
  idr.func @h(%xs: tensor<?x!Below5>, %n: i64) -> tensor<?x!BelowAny> {
    %r = idr.lit.match %n : i64 -> (tensor<?x!BelowAny>) {
    case 1(%key1: i64) {
      %v = idr.call @g(%xs, %n) : (tensor<?x!Below5>, i64) -> tensor<?x!Below5>
      %w = idr.data.reindex %v : tensor<?x!Below5> to tensor<?x!BelowAny>
      idr.yield %w : tensor<?x!BelowAny>
    }
    default(%d: i64) {
      %two = arith.constant 2 : i64
      %m = arith.subi %d, %two : i64
      %v = idr.tail_call @h(%xs, %m) : (tensor<?x!Below5>, i64) -> tensor<?x!BelowAny>
      idr.yield %v : tensor<?x!BelowAny>
    }
    }
    idr.return %r : tensor<?x!BelowAny>
  } loc("h")
  idr.func @g(%xs: tensor<?x!Below5>, %k: i64) -> tensor<?x!Below5> {
    %r = idr.lit.match %k : i64 -> (tensor<?x!Below5>) {
    case 0(%key: i64) {
      idr.yield %xs : tensor<?x!Below5>
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %v = idr.tail_call @g(%xs, %j) : (tensor<?x!Below5>, i64) -> tensor<?x!Below5>
      idr.yield %v : tensor<?x!Below5>
    }
    }
    idr.return %r : tensor<?x!Below5>
  } loc("g")
  idr.func @c(%ys: tensor<?x!BelowAny>, %n: i64) -> tensor<?x!Below5> {
    %r = idr.lit.match %n : i64 -> (tensor<?x!Below5>) {
    case 0(%key0: i64) {
      %v = idr.call @u(%ys, %n) : (tensor<?x!BelowAny>, i64) -> tensor<?x!BelowAny>
      %w = idr.data.reindex %v : tensor<?x!BelowAny> to tensor<?x!Below5>
      idr.yield %w : tensor<?x!Below5>
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %d, %one : i64
      %v = idr.tail_call @c(%ys, %m) : (tensor<?x!BelowAny>, i64) -> tensor<?x!Below5>
      idr.yield %v : tensor<?x!Below5>
    }
    }
    idr.return %r : tensor<?x!Below5>
  } loc("c")
  idr.func @u(%ys: tensor<?x!BelowAny>, %k: i64) -> tensor<?x!BelowAny> {
    %r = idr.lit.match %k : i64 -> (tensor<?x!BelowAny>) {
    case 0(%key: i64) {
      idr.yield %ys : tensor<?x!BelowAny>
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %v = idr.tail_call @u(%ys, %j) : (tensor<?x!BelowAny>, i64) -> tensor<?x!BelowAny>
      idr.yield %v : tensor<?x!BelowAny>
    }
    }
    idr.return %r : tensor<?x!BelowAny>
  } loc("u")
}
