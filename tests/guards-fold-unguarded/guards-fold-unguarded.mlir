// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@unguarded:_/_/_/_/_/_/_/_/_/_/_,returns=@satisfying:-4/3/1/1/-2/#idr.big<-4>/#idr.big<1>/#idr.big<-2>/"bc"/97/99' -o /dev/null
// Every pure total op with a guard, on constants its guard refuses and with
// no guard before it: its folder computes nothing, by guardHolds alone, the
// one reading of the op's guards (Idr_Guarded) every such folder makes, so
// no folder of a guarded op divides by zero, casts a non-finite Double or
// reads past a string. No result of @unguarded is a constant after
// canonicalization. The same ops, with no guard, on the nearest constants
// their guards accept (@satisfying: a divisor of 2 where it was 0, a
// finite Double, a string with a character, an index below the length)
// fold, every one: what stops a fold is the guard's refusal alone.
idr.program @"fold-unguarded" root(@root) stage(first) types #idr.types<> {
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
  idr.func @satisfying() -> (i64, i64, i64, i64, i64, !idr.big, !idr.big, !idr.big, !idr.str, i32,
                             i32) {
    %mseven = arith.constant -7 : i64
    %seven = arith.constant 7 : i64
    %two = arith.constant 2 : i64
    %divs = idr.divs %mseven, %two : i64
    %divu = idr.divu %seven, %two : i64
    %mods = idr.mods %mseven, %two : i64
    %modu = idr.modu %seven, %two : i64
    %finite = arith.constant -2.5 : f64
    %int = idr.to_int %finite : i64
    %bigSeven = idr.constant !idr.big #idr.big<-7>
    %bigTwo = idr.constant !idr.big #idr.big<2>
    %bigDiv = idr.big.div %bigSeven, %bigTwo
    %bigMod = idr.big.mod %bigSeven, %bigTwo
    %fromDouble = idr.big.from_double %finite
    %abc = idr.constant !idr.str "abc"
    %tail = idr.str.tail %abc
    %head = idr.str.head %abc
    %index = idr.str.index %abc, %two
    return %divs, %divu, %mods, %modu, %int, %bigDiv, %bigMod, %fromDouble, %tail, %head, %index
        : i64, i64, i64, i64, i64, !idr.big, !idr.big, !idr.big, !idr.str, i32, i32
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
