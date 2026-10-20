// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(canonicalize,cse)))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=calls-read=@pure_calls:@square,calls-distinct=@pure_calls:@square,call-order=@pure_calls:[@square],call-order=@linear_calls:[@fresh,@fresh],call-order=@crashing_calls:[@guards,@guards,@guards]' -o /dev/null
// A call holds what it may do, and declares it to MLIR as its memory
// effects, so upstream's passes need no table of callees: a call of a
// function that only computes, nothing reading it, is dead code, which
// canonicalize erases, and two equal ones are one value, which CSE merges.
// A linear result is a fresh value each call gives, an allocation of the
// call's own result: two such calls stay two, while one nothing reads
// would still be dead. A call of a function that may crash is neither: it
// stays though nothing reads it, and two equal ones stay two.
idr.program @"call-effects-cse" root(@root) stage(first) types #idr.types<> {
  idr.func effects<none> @square(%x: i64) -> i64 attributes {total} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @pure_calls(%x: i64) -> (i64, i64) {
    %dead = idr.call @square(%x) effects<none> : (i64) -> i64
    %a = idr.call @square(%x) effects<none> : (i64) -> i64
    %b = idr.call @square(%x) effects<none> : (i64) -> i64
    return %a, %b : i64, i64
  }
  idr.func effects<none> @fresh(%s: !idr.str) -> !idr.lin<!idr.str> attributes {total} {
    %l = idr.lin.enter %s : !idr.lin<!idr.str>
    return %l : !idr.lin<!idr.str>
  }
  idr.func @linear_calls(%s: !idr.str) -> (!idr.lin<!idr.str>, !idr.lin<!idr.str>) {
    %a = idr.call @fresh(%s) effects<none> : (!idr.str) -> !idr.lin<!idr.str>
    %b = idr.call @fresh(%s) effects<none> : (!idr.str) -> !idr.lin<!idr.str>
    return %a, %b : !idr.lin<!idr.str>, !idr.lin<!idr.str>
  }
  idr.func effects<crash> @guards(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    return %y : i64
  }
  idr.func @crashing_calls(%x: i64) -> (i64, i64) {
    %unread = idr.call @guards(%x) effects<crash> : (i64) -> i64
    %a = idr.call @guards(%x) effects<crash> : (i64) -> i64
    %b = idr.call @guards(%x) effects<crash> : (i64) -> i64
    return %a, %b : i64, i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
