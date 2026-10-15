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

// The divisor is not zero: idr.check.nonzero guards it.
class Idr_DivisionOp<string mnemonic, bit isQuotient>
    : Idr_Op<mnemonic, [SameOperandsAndResultType, NoMemoryEffect,
                        Idr_Guarded<"rhs", "Nonzero", "division by zero">,
                        DeclareOpInterfaceMethods<ConditionallySpeculatable>]> {
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$lhs, Idr_Int:$rhs);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $lhs `,` $rhs attr-dict `:` type($result)
  }];
  let hasFolder = 1;
  let extraClassDeclaration = "static constexpr bool quotient = "
                              # !if(isQuotient, "true", "false") # ";";
  let extraClassDefinition = [{
    ::mlir::OpFoldResult $cppClass::fold(FoldAdaptor adaptor) {
      return foldDivision(*this, adaptor);
    }
  }];
}

def Idr_DivOp : Idr_DivisionOp<"div", 1> {
  let summary = "Idris div: Euclidean when signed, of a divisor that is not zero";
}
def Idr_ModOp : Idr_DivisionOp<"mod", 0> {
  let summary = "Idris mod: Euclidean when signed, of a divisor that is not zero";
}

// Idris's shifts of a fixed-width integer: the value shifted
// arithmetically by the amount, then wrapped to the type's width. So a
// left shift by the width or more is 0, a right shift by it or more is the
// sign (0 or -1; 0 when unsigned), and a negative amount shifts the other
// way. Defined for every amount, unlike arith's shifts, which are poison
// from the width up.
class Idr_ShiftOp<string mnemonic, bit isLeft>
    : Idr_Op<mnemonic, [Pure, SameOperandsAndResultType]> {
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$lhs, Idr_Int:$rhs);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $lhs `,` $rhs attr-dict `:` type($result)
  }];
  let hasFolder = 1;
  let extraClassDeclaration = "static constexpr bool left = "
                              # !if(isLeft, "true", "false") # ";";
  let extraClassDefinition = [{
    ::mlir::OpFoldResult $cppClass::fold(FoldAdaptor adaptor) {
      return foldShift(*this, adaptor);
    }
  }];
}

def Idr_ShlOp : Idr_ShiftOp<"shl", 1> {
  let summary = "Idris shiftL: defined for every amount, wrapped to the width";
}
def Idr_ShrOp : Idr_ShiftOp<"shr", 0> {
  let summary = "Idris shiftR: arithmetic, defined for every amount";
}

def Idr_ToCharOp : Idr_Op<"to_char", [Pure,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "an integer as a Char: itself if a scalar value, else 0";
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$value);
  let results = (outs I32:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value)
  }];
  let hasFolder = 1;
}

// An Int written as a byte of a buffer, which is 0 to 255: idr.check.byte
// guards it, as Chez's bytevector-u8-set! refuses any other.
def Idr_ToByteOp : Idr_Op<"to_byte", [NoMemoryEffect,
    Idr_Guarded<"value", "Byte", "a byte outside 0 to 255">,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "an Int from 0 to 255 as a byte";
  let arguments = (ins I64:$value);
  let results = (outs I8:$result);
  let assemblyFormat = "$value attr-dict";
  let hasFolder = 1;
}

// Truncates toward zero and wraps to the result width. The Double is
// finite: idr.check.finite guards it.
def Idr_ToIntOp : Idr_Op<"to_int", [Idr_Runtime<"idris_rt_to_int">, NoMemoryEffect,
    Idr_Guarded<"value", "Finite", "cast of a non-finite Double">,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>, Idr_Primitive]> {
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

// The first character of the decimal text of an integer.
def Idr_IntHeadOp : Idr_Op<"int_head", [Pure, Idr_Runtime<"idris_rt_int_head">,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the first character of an integer's decimal text";
  let arguments = (ins UnitAttr:$is_signed, Idr_Int:$value);
  let results = (outs I32:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value)
  }];
}

#endif // IDR_SCALAR_OPS
