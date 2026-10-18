// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-closures=@of_closure,calls=@of_closure:@add,\
// RUN: no-closures=@of_constant,calls=@of_constant:@add,no-closures=@of_constant_data,calls=@of_constant_data:@pick,\
// RUN: no-closures=@force,calls=@force:@delayed,applies=@unknown,no-closures=@of_linear,calls=@of_linear:@add,\
// RUN: no-closures=@of_constant_linear,calls=@of_constant_linear:@once -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --inline --canonicalize \
// RUN: --idr-expect=holds=never-calls=@of_closure:@add,returns=@captures_first:5 -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// Applying a known closure calls its function with the captures first, as
// upstream's func.call_indirect of a constant becomes a direct call; the
// inliner then removes the call. That the captures come first is what a
// closure of a subtraction computes: 7 - 2, not 2 - 7.

!S = !idr.data<"S", plain [@MkS(i64, !idr.str)]>
idr.program @apply root(@root) stage(higher) {
  idr.func @add(%a: i64, %b: i64) -> i64 {
    %r = arith.addi %a, %b : i64
    return %r : i64
  }
  idr.func @delayed(%a: i64) -> i64 {
    %r = arith.muli %a, %a : i64
    return %r : i64
  }
  idr.func @pick(%s: !S, %t: !idr.str, %n: i64) -> i64 {
    return %n : i64
  }
  idr.func @sub(%a: i64, %b: i64) -> i64 {
    %r = arith.subi %a, %b : i64
    return %r : i64
  }

  idr.func @captures_first() -> i64 {
    %c = idr.constant #idr.closure<@sub, [7 : i64]> : !idr.fn<(i64) -> (i64)>
    %two = arith.constant 2 : i64
    %r = idr.apply %c(%two) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }

  idr.func @of_closure(%x: i64, %y: i64) -> i64 {
    %c = idr.closure @add(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %c(%y) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }

  // A constant closure's captures become constants.
  idr.func @of_constant(%y: i64) -> i64 {
    %c = idr.constant #idr.closure<@add, [5 : i64]> : !idr.fn<(i64) -> (i64)>
    %r = idr.apply %c(%y) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }

  // Captures of every kind of constant.
  idr.func @of_constant_data(%n: i64) -> i64 {
    %c = idr.constant #idr.closure<@pick, [#idr.con<!S, @MkS, [1 : i64, "a"]>, "b"]>
       : !idr.fn<(i64) -> (i64)>
    %r = idr.apply %c(%n) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }

  // Forcing a delayed value (a closure of no arguments).
  idr.func @force(%x: i64) -> i64 {
    %d = idr.closure @delayed(%x) : (i64) -> !idr.fn<() -> (i64)>
    %r = idr.apply %d() : !idr.fn<() -> (i64)>
    return %r : i64
  }

  // An unknown closure stays applied.
  idr.func @unknown(%c: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %c(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }

  // An IO action is a linear closure: applying its one use, when it was
  // entered into its linear type from a known closure, calls the function.
  idr.func @of_linear(%x: i64, %y: i64) -> i64 {
    %c = idr.closure @add(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    %l = idr.lin.enter %c : !idr.lin<!idr.fn<(i64) -> (i64)>>
    %f = idr.lin.use %l : !idr.lin<!idr.fn<(i64) -> (i64)>>
    %r = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }

  // A constant closure's capture fills a linear parameter entered into its
  // linear type.
  idr.func @once(%a: !idr.lin<i64>, %b: i64) -> i64 {
    %x = idr.lin.use %a : !idr.lin<i64>
    %r = arith.addi %x, %b : i64
    return %r : i64
  }
  idr.func @of_constant_linear(%y: i64) -> i64 {
    %c = idr.constant #idr.closure<@once, [5 : i64]> : !idr.fn<(i64) -> (i64)>
    %r = idr.apply %c(%y) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
