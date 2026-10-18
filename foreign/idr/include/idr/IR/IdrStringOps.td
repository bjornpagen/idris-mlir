// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops of the idr dialect on strings.

#ifndef IDR_STRING_OPS
#define IDR_STRING_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"

//===----------------------------------------------------------------------===//
// Strings
//===----------------------------------------------------------------------===//

// A string builder allocates its result (MemAlloc).
class Idr_StrBuilderOp<string mnemonic, list<Trait> traits = []>
    : Idr_Op<"str." # mnemonic, traits> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$result);
}

def Idr_StrAppendOp : Idr_StrBuilderOp<"append", [Idr_Runtime<"idris_rt_str_append">, Idr_Primitive,
    DeclareOpInterfaceMethods<Idr_StrBuilderOpInterface>]> {
  let summary = "the concatenation of two strings";
  let arguments = (ins Idr_StrRead:$lhs, Idr_StrRead:$rhs);
  let assemblyFormat = [{
    custom<Read>($lhs, type($lhs), "::idr::StrType::get($_ctxt)") `,`
    custom<Read>($rhs, type($rhs), "::idr::StrType::get($_ctxt)") attr-dict
    custom<ResultAtGrade>(type($result), "::idr::StrType::get($_ctxt)")
  }];
}

def Idr_StrConsOp : Idr_StrBuilderOp<"cons", [Idr_Runtime<"idris_rt_str_cons">, Idr_Primitive,
    DeclareOpInterfaceMethods<Idr_StrBuilderOpInterface>]> {
  let summary = "a character before a string";
  let arguments = (ins I32:$head, Idr_StrRead:$tail);
  let assemblyFormat = [{
    $head `,` custom<Read>($tail, type($tail), "::idr::StrType::get($_ctxt)") attr-dict
    custom<ResultAtGrade>(type($result), "::idr::StrType::get($_ctxt)")
  }];
}

def Idr_StrFromCharOp : Idr_StrBuilderOp<"from_char", [Idr_Runtime<"idris_rt_str_from_char">,
    Idr_Primitive, DeclareOpInterfaceMethods<Idr_StrBuilderOpInterface>]> {
  let summary = "the string of one character";
  let arguments = (ins I32:$value);
  let assemblyFormat = [{
    $value attr-dict custom<ResultAtGrade>(type($result), "::idr::StrType::get($_ctxt)")
  }];
}

// A string built once from a list the Prelude would build a piece at a
// time: pack over a List Char, concat over a List String. The list is a
// box of a nil without fields and a cons of the element and the rest; the
// op walks it twice, once for the size of the result and once to write it.
// The list is base's: a box of a data type of kind `list`, whose body says
// its shape. The walk is the op's own lowering: it calls no runtime
// function of its own.
def Idr_StrPackOp : Idr_StrBuilderOp<"pack", [Idr_Primitive,
    DeclareOpInterfaceMethods<Idr_StrBuilderOpInterface>]> {
  let summary = "the string of a list of characters, built once";
  let arguments = (ins Idr_BaseListOf<[I32]>:$list);
  let assemblyFormat = "$list attr-dict `:` type($list) `->` type($result)";
}

def Idr_StrConcatOp : Idr_StrBuilderOp<"concat", [Idr_Primitive,
    DeclareOpInterfaceMethods<Idr_StrBuilderOpInterface>]> {
  let summary = "the concatenation of a list of strings, built once";
  let arguments = (ins Idr_BaseListOf<[Idr_StrType]>:$list);
  let assemblyFormat = "$list attr-dict `:` type($list) `->` type($result)";
}

// Output of a list pack or concat walks: its characters or its strings,
// written in order, each as put_char or put_str writes it, which is what
// writing the list's pack or concat writes. Output of a pack or a concat
// whose string has no other use becomes this op, and the string is never
// built. Where the op meets the list's constructor it takes one step of
// the walk: the nil writes nothing, and a cell writes its element before
// the rest, so a cell built only to be written is not built. It is IO, as
// the idr.io ops are, but calls no runtime function of its own: its
// lowering walks the list (lib/Conversion). The list is base's, as pack's
// and concat's are.
def Idr_PutListOp : Idr_Op<"io.put_list", [Idr_PerformsIO, Idr_ObservableIO, Idr_Primitive,
    MemoryEffects<[MemRead<Idr_IOResource>, MemWrite<Idr_IOResource>]>]> {
  let summary = "writes the characters or the strings of a list, in order";
  let arguments = (ins Idr_BaseListOf<[I32, Idr_StrType]>:$list, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$list `,` $world attr-dict `:` type($list)";
  let hasCanonicalizer = 1;
}

// The text of a number: one op per meaning, each with the runtime's
// function for it. An integer is read as the op's signedness says, to which
// the operand's constraint extends its C word; a Double has no signedness.
class Idr_StrShowIntOp<string mnemonic, bit isSigned>
    : Idr_StrBuilderOp<mnemonic, [Idr_Runtime<"idris_rt_str_show" # !if(isSigned, "_s", "_u")>,
                                  DeclareOpInterfaceMethods<Idr_StrBuilderOpInterface>]> {
  let arguments = (ins !if(isSigned, Idr_SInt, Idr_UInt):$value);
  let assemblyFormat = [{
    $value attr-dict `:` type($value)
    custom<ResultAtGrade>(type($result), "::idr::StrType::get($_ctxt)")
  }];
  let extraClassDeclaration = "static constexpr bool isSigned = "
                              # !if(isSigned, "true", "false") # ";";
}

def Idr_StrShowSIntOp : Idr_StrShowIntOp<"show_sint", 1> {
  let summary = "the decimal text of a signed integer";
}
def Idr_StrShowUIntOp : Idr_StrShowIntOp<"show_uint", 0> {
  let summary = "the decimal text of an unsigned integer";
}

def Idr_StrShowDoubleOp : Idr_StrBuilderOp<"show_double", [Idr_Runtime<"idris_rt_str_show_f64">,
    DeclareOpInterfaceMethods<Idr_StrBuilderOpInterface>]> {
  let summary = "the text of a Double, as prim__cast_DoubleString writes it";
  let arguments = (ins F64:$value);
  let assemblyFormat = [{
    $value attr-dict custom<ResultAtGrade>(type($result), "::idr::StrType::get($_ctxt)")
  }];
}

def Idr_StrSubstrOp : Idr_StrBuilderOp<"substr", [Idr_Runtime<"idris_rt_str_substr">, Idr_Primitive]> {
  let summary = "the characters of a string from a start, at most a length";
  let arguments = (ins Idr_StrRead:$str, I64:$start, I64:$length);
  let assemblyFormat = [{
    custom<Read>($str, type($str), "::idr::StrType::get($_ctxt)") `,` $start `,` $length attr-dict
    custom<ResultAtGrade>(type($result), "::idr::StrType::get($_ctxt)")
  }];
}

def Idr_StrReverseOp : Idr_StrBuilderOp<"reverse", [Idr_Runtime<"idris_rt_str_reverse">, Idr_Primitive]> {
  let summary = "the characters of a string in reverse order";
  let arguments = (ins Idr_StrRead:$str);
  let assemblyFormat = [{
    custom<Read>($str, type($str), "::idr::StrType::get($_ctxt)") attr-dict
    custom<ResultAtGrade>(type($result), "::idr::StrType::get($_ctxt)")
  }];
}

// The string is not empty: idr.check.nonempty guards it. A new string,
// allocated like a builder's.
def Idr_StrTailOp : Idr_Op<"str.tail", [Idr_Runtime<"idris_rt_str_tail">, Idr_Primitive,
    Idr_Guarded<["str"], Idr_Nonempty, "tail of an empty string">, Idr_GuardedOp]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "a string without its first character, of a string that is not empty";
  let arguments = (ins Idr_StrRead:$str);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$result);
  let assemblyFormat = [{
    custom<Read>($str, type($str), "::idr::StrType::get($_ctxt)") attr-dict
    custom<ResultAtGrade>(type($result), "::idr::StrType::get($_ctxt)")
  }];
}

def Idr_StrLengthOp : Idr_Op<"str.length", [Pure, Idr_Runtime<"idris_rt_str_length">, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the number of characters of a string";
  let arguments = (ins Idr_StrRead:$str);
  let results = (outs I64:$result);
  let assemblyFormat = "custom<Read>($str, type($str), \"::idr::StrType::get($_ctxt)\") attr-dict";
}

// The number of bytes of a string, the length of its UTF-8, interior zeros
// included. Folded by calling the runtime, as str.length is.
def Idr_StrBytesLengthOp : Idr_Op<"str.bytes_length", [Pure, Idr_Runtime<"idris_rt_str_bytes_length">, Idr_Primitive]> {
  let hasFolder = 1;
  let summary = "the number of bytes of a string";
  let arguments = (ins Idr_StrRead:$str);
  let results = (outs I64:$result);
  let assemblyFormat = "custom<Read>($str, type($str), \"::idr::StrType::get($_ctxt)\") attr-dict";
}

// A string by byte offset, as the linear string iterator walks it. Every
// offset has a meaning, the runtime's, so these ops need no guard. Folded
// by calling the runtime.
def Idr_StrScalarAtOp : Idr_Op<"str.scalar_at", [Pure, Idr_Runtime<"idris_rt_str_scalar_at">, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let hasFolder = 1;
  let summary = "the character that starts at a byte offset, 0 at the end";
  let arguments = (ins Idr_StrRead:$str, I64:$offset);
  let results = (outs I32:$result);
  let assemblyFormat = [{
    custom<Read>($str, type($str), "::idr::StrType::get($_ctxt)") `,` $offset attr-dict
  }];
}

def Idr_StrDropBytesOp : Idr_StrBuilderOp<"drop_bytes", [Idr_Runtime<"idris_rt_str_drop_bytes">, Idr_Primitive]> {
  let summary = "the characters of a string from a byte offset on";
  let arguments = (ins Idr_StrRead:$str, I64:$offset);
  let assemblyFormat = [{
    custom<Read>($str, type($str), "::idr::StrType::get($_ctxt)") `,` $offset attr-dict
    custom<ResultAtGrade>(type($result), "::idr::StrType::get($_ctxt)")
  }];
}

// The linear string iterator's step past the character it read: the
// length of the character's UTF-8, a function of the character alone,
// since every string is well-formed UTF-8. The length is the runtime's one
// rule, the one idr.str.from_char encodes a character by, so the iterator
// states none of its own. Folded by calling the runtime.
def Idr_StrScalarBytesOp : Idr_Op<"str.scalar_bytes", [Pure, Idr_Runtime<"idris_rt_str_scalar_bytes">, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let hasFolder = 1;
  let summary = "the number of bytes of a character's UTF-8";
  let arguments = (ins I32:$value);
  let results = (outs I64:$result);
  let assemblyFormat = "$value attr-dict";
}

// The index is at least 0 and below the string's length: idr.check.in_bounds
// guards it, against this string.
def Idr_StrIndexOp : Idr_Op<"str.index", [Idr_Runtime<"idris_rt_str_index">, NoMemoryEffect,
    Idr_Guarded<["index", "str"], Idr_InBounds, "string index out of range">,
    Idr_GuardedOp, ConditionallySpeculatable, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the character at an index within the string";
  let arguments = (ins Idr_StrRead:$str, I64:$index);
  let results = (outs I32:$result);
  let assemblyFormat = [{
    custom<Read>($str, type($str), "::idr::StrType::get($_ctxt)") `,` $index attr-dict
  }];
}

// The string is not empty: idr.check.nonempty guards it.
def Idr_StrHeadOp : Idr_Op<"str.head", [Idr_Runtime<"idris_rt_str_head">, NoMemoryEffect,
    Idr_Guarded<["str"], Idr_Nonempty, "head of an empty string">,
    Idr_GuardedOp, ConditionallySpeculatable, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the first character of a string that is not empty";
  let arguments = (ins Idr_StrRead:$str);
  let results = (outs I32:$result);
  let assemblyFormat = "custom<Read>($str, type($str), \"::idr::StrType::get($_ctxt)\") attr-dict";
  let hasCanonicalizer = 1;
}

def Idr_StrCmpOp : Idr_Op<"str.cmp", [Pure, Idr_Runtime<"idris_rt_str_cmp">]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "compares two strings";
  let arguments = (ins Idr_CmpPredicate:$predicate, Idr_StrRead:$lhs,
                       Idr_StrRead:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = [{
    $predicate custom<Read>($lhs, type($lhs), "::idr::StrType::get($_ctxt)") `,`
    custom<Read>($rhs, type($rhs), "::idr::StrType::get($_ctxt)") attr-dict
  }];
}

// One op for IntN and BitsN: its runtime function's reading of a string has
// no signedness, and the op wraps what it gives to the op's width.
def Idr_StrToIntOp : Idr_Op<"str.to_int", [Pure, Idr_Runtime<"idris_rt_str_to_int">]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "a string as an integer, as prim__cast_StringT reads it";
  let arguments = (ins Idr_StrRead:$str);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = [{
    custom<Read>($str, type($str), "::idr::StrType::get($_ctxt)") attr-dict `:` type($result)
  }];
}

def Idr_StrToDoubleOp : Idr_Op<"str.to_double", [Pure, Idr_Runtime<"idris_rt_str_to_double">, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "a string as a Double, as prim__cast_StringDouble reads it";
  let arguments = (ins Idr_StrRead:$str);
  let results = (outs F64:$result);
  let assemblyFormat = "custom<Read>($str, type($str), \"::idr::StrType::get($_ctxt)\") attr-dict";
}

#endif // IDR_STRING_OPS
