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
    : Idr_Op<"str." # mnemonic, !listconcat(traits, [Idr_CallsRuntime])> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$result);
}

def Idr_StrAppendOp : Idr_StrBuilderOp<"append", [Idr_Primitive]> {
  let summary = "the concatenation of two strings";
  let arguments = (ins Idr_StrType:$lhs, Idr_StrType:$rhs);
  let assemblyFormat = "$lhs `,` $rhs attr-dict custom<StrResult>(type($result))";
}

def Idr_StrConsOp : Idr_StrBuilderOp<"cons", [Idr_Primitive]> {
  let summary = "a character before a string";
  let arguments = (ins I32:$head, Idr_StrType:$tail);
  let assemblyFormat = "$head `,` $tail attr-dict custom<StrResult>(type($result))";
}

def Idr_StrFromCharOp : Idr_StrBuilderOp<"from_char", [Idr_Primitive]> {
  let summary = "the string of one character";
  let arguments = (ins I32:$value);
  let assemblyFormat = "$value attr-dict custom<StrResult>(type($result))";
}

// A string built once from a list the Prelude would build a piece at a
// time: pack over a List Char, concat over a List String. The list is a
// box of a nil without fields and a cons of the element and the rest; the
// op walks it twice, once for the size of the result and once to write it.
// The list is base's: a box of a data type of kind `list`, whose body says
// its shape.
def Idr_StrPackOp : Idr_StrBuilderOp<"pack", [Idr_Primitive]> {
  let summary = "the string of a list of characters, built once";
  let arguments = (ins Idr_SumValue:$list);
  let assemblyFormat = "$list attr-dict `:` type($list) `->` type($result)";
  let hasVerifier = 1;
}

def Idr_StrConcatOp : Idr_StrBuilderOp<"concat", [Idr_Primitive]> {
  let summary = "the concatenation of a list of strings, built once";
  let arguments = (ins Idr_SumValue:$list);
  let assemblyFormat = "$list attr-dict `:` type($list) `->` type($result)";
  let hasVerifier = 1;
}

// Output of a list pack or concat walks: its characters or its strings,
// written in order, each as put_char or put_str writes it, which is what
// writing the list's pack or concat writes. Output of a pack or a concat
// whose string has no other use becomes this op, and the string is never
// built. Where the op meets the list's constructor it takes one step of
// the walk: the nil writes nothing, and a cell writes its element before
// the rest, so a cell built only to be written is not built. It is IO, as
// the idr.io ops are, but calls no runtime function named after it: its
// lowering walks the list (lib/Conversion). The list is base's, as pack's
// and concat's are.
def Idr_PutListOp : Idr_Op<"io.put_list", [Idr_PerformsIO, Idr_ObservableIO, Idr_Primitive,
    MemoryEffects<[MemRead<Idr_IOResource>, MemWrite<Idr_IOResource>]>]> {
  let summary = "writes the characters or the strings of a list, in order";
  let arguments = (ins Idr_SumValue:$list, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = "$list `,` $world attr-dict `:` type($list)";
  let hasVerifier = 1;
  let hasCanonicalizer = 1;
}

// `signed` or `unsigned` for an integer, nothing for a Double.
def Idr_StrShowOp : Idr_StrBuilderOp<"show"> {
  let summary = "the text of a number, as prim__cast_TString writes it";
  let arguments = (ins UnitAttr:$is_signed, AnyTypeOf<[Idr_Int, F64]>:$value);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $value attr-dict `:` type($value) custom<StrResult>(type($result))
  }];
  let hasVerifier = 1;
}

def Idr_StrSubstrOp : Idr_StrBuilderOp<"substr", [Idr_Primitive]> {
  let summary = "the characters of a string from a start, at most a length";
  let arguments = (ins Idr_StrType:$str, I64:$start, I64:$length);
  let assemblyFormat = "$str `,` $start `,` $length attr-dict custom<StrResult>(type($result))";
}

def Idr_StrReverseOp : Idr_StrBuilderOp<"reverse", [Idr_Primitive]> {
  let summary = "the characters of a string in reverse order";
  let arguments = (ins Idr_StrType:$str);
  let assemblyFormat = "$str attr-dict custom<StrResult>(type($result))";
}

// The string is not empty: idr.check.nonempty guards it. A new string,
// allocated like a builder's.
def Idr_StrTailOp : Idr_Op<"str.tail", [Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "a string without its first character, of a string that is not empty";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc]>:$result);
  let assemblyFormat = "$str attr-dict custom<StrResult>(type($result))";
}

def Idr_StrLengthOp : Idr_Op<"str.length", [Pure, Idr_CallsRuntime, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the number of characters of a string";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs I64:$result);
  let assemblyFormat = "$str attr-dict";
}

// The number of bytes of a string, the length of its UTF-8, interior zeros
// included. Folded by calling the runtime, as str.length is.
def Idr_StrBytesLengthOp : Idr_Op<"str.bytes_length", [Pure, Idr_CallsRuntime, Idr_Primitive]> {
  let hasFolder = 1;
  let summary = "the number of bytes of a string";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs I64:$result);
  let assemblyFormat = "$str attr-dict";
}

// A string by byte offset, as the linear string iterator walks it. Every
// offset has a meaning, so these ops need no guard: it is clamped to the
// string's bytes, and an offset inside a character's encoding stands for
// the start of that character. Folded by calling the runtime.
def Idr_StrScalarAtOp : Idr_Op<"str.scalar_at", [Pure, Idr_CallsRuntime, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let hasFolder = 1;
  let summary = "the character that starts at a byte offset, 0 at the end";
  let arguments = (ins Idr_StrType:$str, I64:$offset);
  let results = (outs I32:$result);
  let assemblyFormat = "$str `,` $offset attr-dict";
}

def Idr_StrScalarEndOp : Idr_Op<"str.scalar_end", [Pure, Idr_CallsRuntime, Idr_Primitive,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let hasFolder = 1;
  let summary = "the byte offset after the character at a byte offset";
  let arguments = (ins Idr_StrType:$str, I64:$offset);
  let results = (outs I64:$result);
  let assemblyFormat = "$str `,` $offset attr-dict";
}

def Idr_StrDropBytesOp : Idr_StrBuilderOp<"drop_bytes", [Idr_Primitive]> {
  let summary = "the characters of a string from a byte offset on";
  let arguments = (ins Idr_StrType:$str, I64:$offset);
  let assemblyFormat = "$str `,` $offset attr-dict custom<StrResult>(type($result))";
}

// The index is at least 0 and below the string's length: idr.check.in_bounds
// guards it.
def Idr_StrIndexOp : Idr_Op<"str.index", [Idr_CallsRuntime, NoMemoryEffect,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the character at an index within the string";
  let arguments = (ins Idr_StrType:$str, I64:$index);
  let results = (outs I32:$result);
  let assemblyFormat = "$str `,` $index attr-dict";
}

// The string is not empty: idr.check.nonempty guards it.
def Idr_StrHeadOp : Idr_Op<"str.head", [Idr_CallsRuntime, NoMemoryEffect,
    DeclareOpInterfaceMethods<ConditionallySpeculatable>, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "the first character of a string that is not empty";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs I32:$result);
  let assemblyFormat = "$str attr-dict";
  let hasCanonicalizer = 1;
}

def Idr_StrCmpOp : Idr_Op<"str.cmp", [Pure, Idr_CallsRuntime]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "compares two strings";
  let arguments = (ins Idr_CmpPredicate:$predicate, Idr_StrType:$lhs,
                       Idr_StrType:$rhs);
  let results = (outs I1:$result);
  let assemblyFormat = "$predicate $lhs `,` $rhs attr-dict";
}

def Idr_StrToIntOp : Idr_Op<"str.to_int", [Pure, Idr_CallsRuntime]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "a string as an integer, as prim__cast_StringT reads it";
  let arguments = (ins UnitAttr:$is_signed, Idr_StrType:$str);
  let results = (outs Idr_Int:$result);
  let assemblyFormat = [{
    custom<Signedness>($is_signed) `` $str attr-dict `:` type($result)
  }];
}

def Idr_StrToDoubleOp : Idr_Op<"str.to_double", [Pure, Idr_CallsRuntime, Idr_Primitive]> {
  // Folded by calling the runtime (lib/IR/Fold).
  let hasFolder = 1;
  let summary = "a string as a Double, as prim__cast_StringDouble reads it";
  let arguments = (ins Idr_StrType:$str);
  let results = (outs F64:$result);
  let assemblyFormat = "$str attr-dict";
}

#endif // IDR_STRING_OPS
