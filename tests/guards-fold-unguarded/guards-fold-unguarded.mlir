// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@unguarded:_/_/_/_/_/_/_/_/_/_/_ -o /dev/null
// Every pure total op with a guard, on constants its guard refuses and with
// no guard before it: its folder computes nothing, by guardHolds alone, the
// one reading of the op's guards (Idr_Guarded) every such folder makes, so
// no folder of a guarded op divides by zero, casts a non-finite Double or
// reads past a string. No result of @unguarded is a constant after
// canonicalization.
idr.program @"fold-unguarded" root(@root) stage(first) {
  idr.func @unguarded() -> (i64, i64, i64, i64, i64, !idr.big, !idr.big, !idr.big, !idr.str, i32,
                            i32) {
    %seven = arith.constant 7 : i64
    %zero = arith.constant 0 : i64
    %divs = idr.divs %seven, %zero : i64
    %divu = idr.divu %seven, %zero : i64
    %mods = idr.mods %seven, %zero : i64
    %modu = idr.modu %seven, %zero : i64
    %nan = arith.constant 0x7FF8000000000000 : f64
    %int = idr.to_int %nan : i64
    %bigSeven = idr.constant !idr.big #idr.big<7>
    %bigZero = idr.constant !idr.big #idr.big<0>
    %bigDiv = idr.big.div %bigSeven, %bigZero
    %bigMod = idr.big.mod %bigSeven, %bigZero
    %inf = arith.constant 0x7FF0000000000000 : f64
    %fromDouble = idr.big.from_double %inf
    %empty = idr.constant !idr.str ""
    %tail = idr.str.tail %empty
    %head = idr.str.head %empty
    %abc = idr.constant !idr.str "abc"
    %three = arith.constant 3 : i64
    %index = idr.str.index %abc, %three
    return %divs, %divu, %mods, %modu, %int, %bigDiv, %bigMod, %fromDouble, %tail, %head, %index
        : i64, i64, i64, i64, i64, !idr.big, !idr.big, !idr.big, !idr.str, i32, i32
  }
  // The program's root, which the function above is no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
