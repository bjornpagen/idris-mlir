// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops of the idr dialect on Integers and naturals.

#ifndef IDR_BIG_OPS
#define IDR_BIG_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"

//===----------------------------------------------------------------------===//
// Bigs
//===----------------------------------------------------------------------===//

// An op that makes a big allocates its result (MemAlloc).
class Idr_BigBinaryOp<string mnemonic, string what, list<Trait> traits = []>
    : Idr_Op<"big." # mnemonic, !listconcat([Idr_CallsRuntime, Idr_Primitive], traits)> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = what # " of two bigs";
  let arguments = (ins Idr_BigType:$lhs, Idr_BigType:$rhs);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict custom<BigResult>(type($result))";
}

// The sum and the product of two naturals are natural, so these take
// Integers or naturals, and give what they take: Nat's plus and mult are
// these ops. The type is written only for naturals: `: !idr.nat`.
class Idr_BigNaturalOp<string mnemonic, string what>
    : Idr_Op<"big." # mnemonic, [Idr_CallsRuntime, Idr_Primitive, AllTypesMatch<["lhs", "rhs"]>,
                                 Idr_ResultCarriesOperand,
                                 DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = what # " of two bigs or two naturals";
  let arguments = (ins Idr_BigOrNat:$lhs, Idr_BigOrNat:$rhs);
  let results = (outs Res<Idr_BigOrNatValue, "", [MemAlloc]>:$result);
  // The operands' type, written for naturals; the result's when it is
  // the operands' at another grade: `-> !idr.own<!idr.nat>`.
  let assemblyFormat = [{
    $lhs `,` $rhs attr-dict custom<BigResult>(type($lhs))
    custom<NaturalResult>(type($result), ref(type($lhs)))
  }];
}

def Idr_BigAddOp : Idr_BigNaturalOp<"add", "the sum">;
def Idr_BigSubOp : Idr_BigBinaryOp<"sub", "the difference", [DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]>;
def Idr_BigMulOp : Idr_BigNaturalOp<"mul", "the product">;
def Idr_BigAndOp : Idr_BigBinaryOp<"and", "the bitwise and">;
def Idr_BigOrOp : Idr_BigBinaryOp<"or", "the bitwise or">;
def Idr_BigXorOp : Idr_BigBinaryOp<"xor", "the bitwise xor">;

// Integer's shifts: the value's infinite two's complement moved by the
// amount, left or right, the other way when the amount is negative. A left
// shift is value * 2^amount and a right shift the floor of value / 2^amount,
// so every amount has a value, and a shift toward zero or of 0 has one for
// any amount; one too large to hold is exhausted memory, unmodelled as it is
// for idr.big.mul, so the ops get no Idr_MayCrash. The amount is an Integer,
// as Idris types the primitive; base's Bits Integer passes a Nat's. A left
// shift's result may be far larger than its operands, so its folder folds
// only a constant within idr::constantBytes.
class Idr_BigShiftOp<string mnemonic, bit isLeft>
    : Idr_Op<"big." # mnemonic, [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let arguments = (ins Idr_BigType:$value, Idr_BigType:$amount);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value `,` $amount attr-dict custom<BigResult>(type($result))";
  let extraClassDeclaration = "static constexpr bool left = "
                              # !if(isLeft, "true", "false") # ";";
}

def Idr_BigShlOp : Idr_BigShiftOp<"shl", 1> {
  let summary = "a big shifted left, Integer's shiftL";
}
def Idr_BigShrOp : Idr_BigShiftOp<"shr", 0> {
  let summary = "a big shifted right, Integer's shiftR, filling with its sign";
}

// The divisor is not zero: idr.check.nonzero guards it.
class Idr_BigDivisionOp<string mnemonic, string what>
    : Idr_Op<"big." # mnemonic, [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = what # " of two bigs, as Integer's div and mod, by a divisor that is not zero";
  let arguments = (ins Idr_BigType:$lhs, Idr_BigType:$rhs);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict custom<BigResult>(type($result))";
}

def Idr_BigDivOp : Idr_BigDivisionOp<"div", "the quotient">;
def Idr_BigModOp : Idr_BigDivisionOp<"mod", "the remainder">;

def Idr_BigNegOp : Idr_Op<"big.neg", [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the negation of a big";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict custom<BigResult>(type($result))";
}

// The frontend writes it where a match on a natural found it is not zero,
// so the value visibly shrinks: the passes see structural descent, not
// arithmetic. That the operand is not zero is also why the result is
// natural. A small operand's predecessor is computed inline; a GMP one's
// is a new big, so the op allocates its result like the other big ops.
def Idr_BigPredOp : Idr_Op<"big.pred", [Idr_CallsRuntime,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the predecessor of a natural that is not zero";
  let arguments = (ins Idr_NatType:$value);
  let results = (outs Res<Idr_NatValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict custom<NatResult>(type($result))";
}

// Two naturals compare as the Integers they are: Nat's equalNat and
// compareNat are this op. The type is written only for naturals.
def Idr_BigCmpOp : Idr_Op<"big.cmp", [Pure, Idr_CallsRuntime,
    AllTypesMatch<["lhs", "rhs"]>, DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "compares two bigs or two naturals";
  let arguments = (ins Idr_CmpPredicate:$predicate, Idr_BigOrNat:$lhs,
                       Idr_BigOrNat:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = "$predicate $lhs `,` $rhs attr-dict custom<BigResult>(type($lhs))";
}

// A natural as the Integer it is (Nat's natToInteger): the same big under
// another type. It costs nothing at runtime, and hands its operand's
// reference to its result.
def Idr_NatToBigOp : Idr_Op<"nat.to_big", [Idr_ConsumesOnly<"0">, Idr_Primitive,
    TypesMatchWith<"the Integer is the natural at its grade", "value", "result",
                   "::idr::graded(::idr::gradeOf($_self), ::idr::BigType::get($_self.getContext()))">,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let hasFolder = 1;
  let summary = "a natural as an Integer";
  let arguments = (ins Idr_NatValue:$value);
  let results = (outs Idr_BigValue:$result);
  let assemblyFormat = "$value attr-dict custom<NatResult>(type($value))";
}

// The only op that makes a natural of an Integer, so the one that must
// keep it non-negative: a negative Integer is 0, as Nat's integerToNat
// and minus (the difference of the Integers, clamped) say.
def Idr_NatFromBigOp : Idr_Op<"nat.from_big", [Idr_CallsRuntime, Idr_Primitive, DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "an Integer as a natural, 0 if it is negative";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs Res<Idr_NatValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict custom<NatResult>(type($result))";
}

// An integer as an Integer, or, read as unsigned, as a natural: an unsigned
// integer is never negative, so the verifier admits a natural result only
// for one (idr-narrow writes it where a natural leaves a word).
def Idr_BigFromIntOp : Idr_Op<"big.from_int", [Idr_CallsRuntime, DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let hasVerifier = 1;
  let summary = "an integer as a big or, unsigned, as a natural";
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$value);
  let results = (outs Res<Idr_BigOrNatValue, "", [MemAlloc]>:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value)
    custom<BigResult>(type($result))
  }];
}

// The big or natural of a word proved to fit the small range: idr-narrow
// writes it where a web of values it proved small meets a big. A small holds
// no reference and allocates nothing, so counting has nothing to do for it.
// A word outside the small range has no big here, as an overflowing nsw add
// has no sum: the pass that writes the op is the proof.
def Idr_BigSmallOp : Idr_Op<"big.small", [Pure, DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let hasFolder = 1;
  let summary = "the small big or natural of a word that fits";
  let arguments = (ins I64:$value);
  let results = (outs Idr_BigOrNatValue:$result);
  let assemblyFormat = "$value attr-dict `:` type($result)";
}

// A natural's value is its Integer's, so both convert alike.
def Idr_BigToIntOp : Idr_Op<"big.to_int", [Pure, Idr_CallsRuntime, Idr_Primitive, DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "a big or a natural as an integer, wrapped to its width";
  let arguments = (ins Idr_BigOrNat:$value);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = "$value attr-dict `:` type($result) custom<BigResult>(type($value))";
}

// The Double is finite: idr.check.finite guards it.
def Idr_BigFromDoubleOp : Idr_Op<"big.from_double", [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "a finite Double truncated to a big";
  let arguments = (ins F64:$value);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict custom<BigResult>(type($result))";
}

def Idr_BigToDoubleOp : Idr_Op<"big.to_double", [Pure, Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "a big as the nearest Double";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs F64:$result);
  let assemblyFormat = "$value attr-dict";
}

def Idr_BigShowOp : Idr_Op<"big.show", [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the decimal text of a big";
  let arguments = (ins Idr_BigType:$value);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$value attr-dict custom<StrResult>(type($result))";
}

def Idr_BigFromStrOp : Idr_Op<"big.from_str", [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "a string as a big, as prim__cast_StringInteger reads it";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs Res<Idr_BigValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$str attr-dict custom<BigResult>(type($result))";
}

def Idr_ArrayValue : Type<CPred<"::idr::isArray(::idr::unrestricted($_self))">,
                          "an array of rank 0 or 1 at any grade", "::mlir::Type">;
// What has a length: an array of one dimension, as a buffer and the index
// space of a loop are.
def Idr_Rank1ArrayValue : Type<CPred<"::idr::isRank1Array(::idr::unrestricted($_self))">,
                               "an array of one dimension at any grade", "::mlir::Type">;

#endif // IDR_BIG_OPS
