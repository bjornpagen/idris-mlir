// RUN: idris-mlir-opt %s -split-input-file -o /dev/null
// RUN: %status 1 idris-mlir-opt %s -split-input-file --canonicalize -o /dev/null 2> %t.err
// RUN: FileCheck %s --implicit-check-not=error: < %t.err
// A call consumes the references its callee owns, and no effect says so: an
// unused call of a callee that only computes is dead code to canonicalize.
// In the owned stage, erasing one leaves a reference that no path consumes
// any more: the argument the call consumed, or the argument a constructor
// consumed, which went with the call it was given to. The owned stage's
// verifier, which runs after every pass, refuses that: the pass fails
// instead of leaking a cell. As written, every reference is consumed.
// CHECK: error: 'func.return' op returns while a value still holds a reference
// CHECK: error: 'func.return' op returns while a value still holds a reference

module attributes {idr.program} {
  func.func private @measure(%s: !idr.own<!idr.str>) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length %v
    idr.drop %s : !idr.own<!idr.str>
    return %n : i64
  }
  func.func private @unused(%s: !idr.own<!idr.str>) -> i64 {
    %n = func.call @measure(%s) : (!idr.own<!idr.str>) -> i64
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

module attributes {idr.program} {
  idr.data @Box box {
    idr.ctor @Box (!idr.str)
  }
  func.func private @size(%b: !idr.own<!idr.box<@Box>>) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %v = idr.borrow %b : !idr.own<!idr.box<@Box>>
    %s = idr.field %v[@Box, 0] : !idr.box<@Box> -> !idr.str
    %n = idr.str.length %s
    idr.drop %b : !idr.own<!idr.box<@Box>>
    return %n : i64
  }
  func.func private @boxed(%s: !idr.own<!idr.str>) -> i64 {
    %b = idr.con @Box::@Box(%s) : (!idr.own<!idr.str>) -> !idr.own<!idr.box<@Box>>
    %n = func.call @size(%b) : (!idr.own<!idr.box<@Box>>) -> i64
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
