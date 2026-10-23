// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded})' -o /dev/null
// Before the stage before counting, a value may cross an edge at a hold
// that fits the one asked; from that stage on every edge is exact, so the
// specializer makes each crossing it leaves exact once its function is
// final, sharing the value down to the hold asked. A string literal is
// static data, which nothing frees and no count writes. @pick yields one
// into its match, whose result is a counted string, as its other region
// yields the counted string its own tail call gives; @word returns one at
// its counted result. Both cross at the counted hold as written, which the
// first-order stage admits, and the module verifies at the graded stage,
// where each edge's types are compared exactly, only where each literal is
// shared down to the counted string its edge asks: a static cell's count
// is never touched, so counting it as a counted string changes nothing at
// run time. @main prints what each gives, twice, so each returns to more
// than one place and none becomes a join point of its one tail caller.
!Str = !idr.graded<many, static, !idr.str>
idr.program @crossings root(@main) stage(first) {
  idr.func @main() {
    %two = arith.constant 2 : i64
    %a = idr.call @pick(%two) <{tail_kind = nontail}> : (i64) -> !idr.str
    idr.io.put_str %a : (!idr.str) -> ()
    %b = idr.call @pick(%two) <{tail_kind = nontail}> : (i64) -> !idr.str
    idr.io.put_str %b : (!idr.str) -> ()
    %c = idr.call @word(%two) <{tail_kind = nontail}> : (i64) -> !idr.str
    idr.io.put_str %c : (!idr.str) -> ()
    %d = idr.call @word(%two) <{tail_kind = nontail}> : (i64) -> !idr.str
    idr.io.put_str %d : (!idr.str) -> ()
    idr.return
  }
  idr.func @pick(%k: i64) -> !idr.str {
    %r = idr.lit.match %k : i64 -> (!idr.str) {
    case 0(%key: i64) {
      %zero = idr.constant !Str "zero"
      idr.yield %zero : !Str
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.call @pick(%j) <{tail_kind = tail}> : (i64) -> !idr.str
      idr.yield %again : !idr.str
    }
    }
    idr.return %r : !idr.str
  } loc("pick")
  idr.func @word(%k: i64) -> !idr.str {
    %word = idr.constant !Str "word"
    idr.return %word : !Str
  } loc("word")
}
