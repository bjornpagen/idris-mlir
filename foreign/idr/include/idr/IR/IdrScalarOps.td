// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops of the idr dialect on fixed-width integers and doubles.

#ifndef IDR_SCALAR_OPS
#define IDR_SCALAR_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"

//===----------------------------------------------------------------------===//
// Scalars
//===----------------------------------------------------------------------===//

// Idris's IntN and BitsN share one signless integer type and differ in
// their operations, so each operation that reads a sign is one op per
// signedness, as arith's divsi and divui are: each pair below is one class
// whose `isSigned` its folder, its range and its lowering read.

// The divisor is not zero: idr.check.nonzero guards it. A signed quotient
// and remainder are Euclidean, an unsigned one's those of the naturals the
// bits are.
class Idr_DivisionOp<string mnemonic, bit isQuotient, bit isSigned>
    : Idr_Op<mnemonic, [SameOperandsAndResultType, NoMemoryEffect,
                        Idr_Guarded<["rhs"], Idr_Nonzero, "division by zero">,
                        Idr_GuardedOp, ConditionallySpeculatable]> {
  let arguments = (ins Idr_Int:$lhs, Idr_Int:$rhs);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict `:` type($result)";
  let hasFolder = 1;
  let extraClassDeclaration = "static constexpr bool quotient = "
                              # !if(isQuotient, "true", "false") # ";\n"
                              # "static constexpr bool isSigned = "
                              # !if(isSigned, "true", "false") # ";";
  let extraClassDefinition = [{
    ::mlir::OpFoldResult $cppClass::fold(FoldAdaptor adaptor) {
      return foldDivision(*this, adaptor);
    }
  }];
}

def Idr_DivSOp : Idr_DivisionOp<"divs", 1, 1> {
  let summary = "Idris div of a signed integer: Euclidean, by a divisor that is not zero";
}
def Idr_DivUOp : Idr_DivisionOp<"divu", 1, 0> {
  let summary = "Idris div of an unsigned integer, by a divisor that is not zero";
}
def Idr_ModSOp : Idr_DivisionOp<"mods", 0, 1> {
  let summary = "Idris mod of a signed integer: Euclidean, by a divisor that is not zero";
}
def Idr_ModUOp : Idr_DivisionOp<"modu", 0, 0> {
  let summary = "Idris mod of an unsigned integer, by a divisor that is not zero";
}

// Idris's shifts of a fixed-width integer: the value shifted by the
// amount, then wrapped to the type's width. So a left shift by the width or
// more is 0, and a right shift by it or more is the fill: a signed value's
// sign (0 or -1), an unsigned value's 0. A signed op reads a negative
// amount as a shift the other way. Defined for every amount, unlike arith's
// shifts, which are poison from the width up.
class Idr_ShiftOp<string mnemonic, bit isLeft, bit isSigned>
    : Idr_Op<mnemonic, [Pure, SameOperandsAndResultType]> {
  let arguments = (ins Idr_Int:$lhs, Idr_Int:$rhs);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict `:` type($result)";
  let hasFolder = 1;
  let extraClassDeclaration = "static constexpr bool left = "
                              # !if(isLeft, "true", "false") # ";\n"
                              # "static constexpr bool isSigned = "
                              # !if(isSigned, "true", "false") # ";";
  let extraClassDefinition = [{
    ::mlir::OpFoldResult $cppClass::fold(FoldAdaptor adaptor) {
      return foldShift(*this, adaptor);
    }
  }];
}

def Idr_ShlSOp : Idr_ShiftOp<"shls", 1, 1> {
  let summary = "Idris shiftL of a signed integer: defined for every amount, wrapped to the width";
}
def Idr_ShlUOp : Idr_ShiftOp<"shlu", 1, 0> {
  let summary = "Idris shiftL of an unsigned integer: defined for every amount, wrapped to the width";
}
def Idr_ShrSOp : Idr_ShiftOp<"shrs", 0, 1> {
  let summary = "Idris shiftR of a signed integer: filling with its sign, defined for every amount";
}
def Idr_ShrUOp : Idr_ShiftOp<"shru", 0, 0> {
  let summary = "Idris shiftR of an unsigned integer: filling with zeros, defined for every amount";
}

// An integer as a Char: itself if it is a scalar value, else 0. A negative
// signed integer is no scalar value; an unsigned one is the natural its
// bits are.
class Idr_ToCharOp<string mnemonic, bit isSigned>
    : Idr_Op<mnemonic, [Pure,
        DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let arguments = (ins Idr_Int:$value);
  let results = (outs I32:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
  let hasFolder = 1;
  let extraClassDeclaration = "static constexpr bool isSigned = "
                              # !if(isSigned, "true", "false") # ";";
}

def Idr_ToCharSOp : Idr_ToCharOp<"to_char_s", 1> {
  let summary = "a signed integer as a Char: itself if a scalar value, else 0";
}
def Idr_ToCharUOp : Idr_ToCharOp<"to_char_u", 0> {
  let summary = "an unsigned integer as a Char: itself if a scalar value, else 0";
}

// Truncates toward zero and wraps to the result width. The Double is
// finite: idr.check.finite guards it.
def Idr_ToIntOp : Idr_Op<"to_int", [Idr_Runtime<"idris_rt_to_int">, NoMemoryEffect,
    Idr_Guarded<["value"], Idr_Finite, "cast of a non-finite Double">,
    Idr_GuardedOp, ConditionallySpeculatable, Idr_Primitive]> {
  let summary = "a finite Double as an integer, truncated and wrapped";
  let arguments = (ins F64:$value);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = "$value attr-dict `:` type($result)";
  let hasFolder = 1;
}

// The first character of prim__cast_DoubleString.
def Idr_DoubleHeadOp : Idr_Op<"double_head", [Pure, Idr_Runtime<"idris_rt_double_head">,
    Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the first character of a Double's text";
  let arguments = (ins F64:$value);
  let results = (outs I32:$result);
  let assemblyFormat = "$value attr-dict";
}

// The first character of the decimal text of an integer, read as the op's
// signedness says: the runtime's function of that signedness, whose C word
// the operand's constraint extends the integer to.
class Idr_IntHeadOp<string mnemonic, bit isSigned>
    : Idr_Op<mnemonic, [Pure, Idr_Runtime<"idris_rt_int_head" # !if(isSigned, "_s", "_u")>,
        DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let arguments = (ins !if(isSigned, Idr_SInt, Idr_UInt):$value);
  let results = (outs I32:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
  let extraClassDeclaration = "static constexpr bool isSigned = "
                              # !if(isSigned, "true", "false") # ";";
}

def Idr_IntHeadSOp : Idr_IntHeadOp<"int_head_s", 1> {
  let summary = "the first character of a signed integer's decimal text";
}
def Idr_IntHeadUOp : Idr_IntHeadOp<"int_head_u", 0> {
  let summary = "the first character of an unsigned integer's decimal text";
}

#endif // IDR_SCALAR_OPS
