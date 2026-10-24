-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The ops on strings. Each is a runtime function, which the folder
||| computes by calling it, but for a list's pack and concat, which build
||| their string in one walk of the list, their own lowering. A builder of a
||| new string acquires nothing before counting. Output of a string is IO's
||| (`Spec.Ops.IO`); writing a built string in pieces, and reading the head
||| of one, are rules (`Spec.Ops.Rewrites`); a number's text made only to be
||| written is written by its show's writer, with no string.
module IdrisMLIR.Spec.Ops.Strings

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Runtime.Helpers
import IdrisMLIR.Spec.Ops.IO
import IdrisMLIR.Spec.Ops.Numeric
import IdrisMLIR.Spec.Ops.Shapes
import IdrisMLIR.Spec.Ops.Values

import Data.List1
-- `builder`'s and `reader`'s automatic proofs are searched where they are written.
import public Data.So
import Data.Vect

%default total

||| A builder whose string is never empty: one built with a character or a
||| number in it. A guard that a string is not empty folds away on one, and
||| the e-graph reads the trait (`NeverEmptyString`).
public export
neverEmpty : TraitDef
neverEmpty = MkTraitDef "NeverEmpty" (says "the string it builds has a character at least")

||| A builder of a new string by a runtime function, its operands as the
||| function takes them and its string as the function gives it.
public export
builder : {i : Nat} -> (m : Mnemonic) -> (f : RuntimeFunction i 1) -> List (Trait i 1)
       -> Doc
       -> {auto 0 named : So (distinct (groupNames (operandsOf f) (resultsOf f) [] []))}
       -> Op i 1 0 0
builder m f traits d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = operandsOf f
  , outs = resultsOf f
  , attrs = []
  , regions = []
  , traits = traits
  , interfaces = []
  , effects = builds 0 Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime f
  , verify = DeclarationOnly
  , format = plain i
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = d
  }

||| The runtime's concatenation is of the two strings' bytes, so it is
||| associative, and the empty string is its identity, on either side: laws
||| the e-graph and the accumulator read. Not commutative, which neither
||| needs: an accumulator combines on the side the call was on.
public export
strAppend : Op 2 1 0 0
strAppend =
  { laws := [Associative, Identity ""] }
  (builder "str.append" (MkRuntimeFunction "str_append" [str "lhs", str "rhs"] (returnsStr "result")) []
    (says "the concatenation of two strings"))

public export
strCons : Op 2 1 0 0
strCons = builder "str.cons" (MkRuntimeFunction "str_cons" [word32 "head", str "tail"] (returnsStr "result"))
  [OurTrait neverEmpty]
  (says "a character before a string")

public export
strFromChar : Op 1 1 0 0
strFromChar = builder "str.from_char" (MkRuntimeFunction "str_from_char" [word32 "value"] (returnsStr "result"))
  [OurTrait neverEmpty]
  (says "the string of one character")

------------------------------------------------------------------------------
-- A number's text, and its output
------------------------------------------------------------------------------

||| The runtime function that writes the text a show's function gives,
||| where the output stands, through the output buffer and with no string:
||| the runtime's two entries share the formatter, and this one takes the
||| show's operand as the show's function takes it, so the two cannot
||| disagree on it. Writing is IO's, so it returns nothing.
public export
writerOf : Ident -> Symbol -> RuntimeFunction 1 1 -> Line -> RuntimeHelper
writerOf name sym shown doc =
  let value = head shown.takes in MkRuntimeHelper name sym [(value.kind, value.operand.name)] HelperNothing doc

||| A show whose text an output of it alone writes with the show's writer
||| (`ShownOutput<Op>`): what the lowering emits for a string the show makes
||| only to write, so `print` of a number builds no string.
public export
shownOutput : RuntimeHelper -> Specialized
shownOutput writer = MkSpecialized "ShownOutput" [("writer", HelperConstant writer)]

showSigned : RuntimeFunction 1 1
showSigned = MkRuntimeFunction "str_show_s" [extended Signed "value"] (returnsStr "result")

showUnsigned : RuntimeFunction 1 1
showUnsigned = MkRuntimeFunction "str_show_u" [extended Unsigned "value"] (returnsStr "result")

showDouble : RuntimeFunction 1 1
showDouble = MkRuntimeFunction "str_show_f64" [float64 "value"] (returnsStr "result")

public export
putSigned : RuntimeHelper
putSigned = writerOf "ioPutS" "io_put_s" showSigned
  "writes the decimal text of a signed integer to standard output"

public export
putUnsigned : RuntimeHelper
putUnsigned = writerOf "ioPutU" "io_put_u" showUnsigned
  "writes the decimal text of an unsigned integer to standard output"

public export
putDouble : RuntimeHelper
putDouble = writerOf "ioPutF64" "io_put_f64" showDouble
  "writes the text of a Double to standard output, as str_show_f64 makes it"

public export
strShowSint : Op 1 1 0 0
strShowSint =
  { specializations := [shownOutput putSigned] }
  (builder "str.show_sint" showSigned [OurTrait neverEmpty]
    (says "the decimal text of a signed integer"))

public export
strShowUint : Op 1 1 0 0
strShowUint =
  { specializations := [shownOutput putUnsigned] }
  (builder "str.show_uint" showUnsigned [OurTrait neverEmpty]
    (says "the decimal text of an unsigned integer"))

public export
strShowDouble : Op 1 1 0 0
strShowDouble =
  { specializations := [shownOutput putDouble] }
  (builder "str.show_double" showDouble [OurTrait neverEmpty]
    (says "the text of a Double, as prim__cast_DoubleString writes it"))

------------------------------------------------------------------------------
-- Other builders
------------------------------------------------------------------------------

public export
strSubstr : Op 3 1 0 0
strSubstr = builder "str.substr"
  (MkRuntimeFunction "str_substr" [str "str", word64 "start", word64 "length"] (returnsStr "result")) []
  (says "the characters of a string from a start, at most a length")

public export
strReverse : Op 1 1 0 0
strReverse = builder "str.reverse" (MkRuntimeFunction "str_reverse" [str "str"] (returnsStr "result")) []
  (says "the characters of a string in reverse order")

||| A string by byte offset, as the linear string iterator walks it: every
||| offset has a meaning, the runtime's, so no guard.
public export
strDropBytes : Op 2 1 0 0
strDropBytes = builder "str.drop_bytes"
  (MkRuntimeFunction "str_drop_bytes" [str "str", word64 "offset"] (returnsStr "result")) []
  (says "the characters of a string from a byte offset on")

||| A string without its first character, of a string that is not empty,
||| which `idr.check.nonempty` guards.
public export
strTail : Op 1 1 0 0
strTail =
  { guards := [MkGuard NonEmpty [0] TailOfEmptyString]
  , speculation := Conditionally }
  (builder "str.tail" (MkRuntimeFunction "str_tail" [str "str"] (returnsStr "result")) []
    (says "a string without its first character, of a string that is not empty"))

------------------------------------------------------------------------------
-- What a string gives
------------------------------------------------------------------------------

||| A runtime function of a string that gives no new string, its result as
||| the function gives it, its type the one its constraint fixes.
public export
reader : {i : Nat} -> (m : Mnemonic) -> (f : RuntimeFunction i 1)
      -> List InterfaceUse -> Doc
      -> {auto 0 named : So (distinct (groupNames (operandsOf f) (resultsOf f) [] []))}
      -> Op i 1 0 0
reader m f ifaces d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = operandsOf f
  , outs = resultsOf f
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = ifaces
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime f
  , verify = DeclarationOnly
  , format = plain i
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = d
  , typing = fixedTypes (resultsOf f)
  }

ranges : InterfaceUse
ranges = Declares InferIntRange ["inferResultRanges"]

public export
strLength : Op 1 1 0 0
strLength = reader "str.length" (MkRuntimeFunction "str_length" [str "str"] (returnsWord64 "result")) [ranges]
  (says "the number of characters of a string")

||| The length of a string's UTF-8, interior zeros included.
public export
strBytesLength : Op 1 1 0 0
strBytesLength = reader "str.bytes_length"
  (MkRuntimeFunction "str_bytes_length" [str "str"] (returnsWord64 "result")) []
  (says "the number of bytes of a string")

public export
strScalarAt : Op 2 1 0 0
strScalarAt = reader "str.scalar_at"
  (MkRuntimeFunction "str_scalar_at" [str "str", word64 "offset"] (returnsWord32 "result")) [ranges]
  (says "the character that starts at a byte offset, 0 at the end")

||| The iterator's step past a character it read: the length of its UTF-8,
||| the runtime's one rule, which the string's encoding is.
public export
strScalarBytes : Op 1 1 0 0
strScalarBytes = reader "str.scalar_bytes"
  (MkRuntimeFunction "str_scalar_bytes" [word32 "value"] (returnsWord64 "result")) [ranges]
  (says "the number of bytes of a character's UTF-8")

||| The character at an index of the string, which `idr.check.in_bounds`
||| guards against this very string.
public export
strIndex : Op 2 1 0 0
strIndex =
  { guards := [MkGuard InBounds [1, 0] StringIndexOutOfRange]
  , speculation := Conditionally }
  (reader "str.index" (MkRuntimeFunction "str_index" [str "str", word64 "index"] (returnsWord32 "result")) []
    (says "the character at an index within the string"))

||| The first character of a string that is not empty, which
||| `idr.check.nonempty` guards.
public export
strHead : Op 1 1 0 0
strHead =
  { guards := [MkGuard NonEmpty [0] HeadOfEmptyString]
  , speculation := Conditionally }
  (reader "str.head" (MkRuntimeFunction "str_head" [str "str"] (returnsWord32 "result")) []
    (says "the first character of a string that is not empty"))

public export
strCmp : Op 2 1 1 0
strCmp = MkOp
  { home = InIdr
  , mnemonic = "str.cmp"
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = [property "predicate" (EnumProperty comparisonEnum)]
  , regions = []
  , traits = []
  , interfaces = []
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
  , verify = DeclarationOnly
  , format = attrFirst 2 0
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "compares two strings"
  , typing = fixedTypes (resultsOf runtime)
  }
  where
    runtime : RuntimeFunction 2 1
    runtime = MkRuntimeFunction "str_cmp" [str "lhs", str "rhs"] (returnsOrder "result")

||| One op for IntN and BitsN: the runtime's reading of a string has no
||| signedness, and the op wraps what it gives to its width.
public export
strToInt : Op 1 1 0 0
strToInt = reader "str.to_int" (MkRuntimeFunction "str_to_int" [str "str"] (returnsWrapped "result")) []
  (says "a string as an integer, as prim__cast_StringT reads it")

public export
strToDouble : Op 1 1 0 0
strToDouble = reader "str.to_double" (MkRuntimeFunction "str_to_double" [str "str"] (returnsFloat64 "result")) []
  (says "a string as a Double, as prim__cast_StringDouble reads it")

------------------------------------------------------------------------------
-- A string of a list
------------------------------------------------------------------------------

||| A string of a list the Prelude would build a piece at a time: pack over
||| a list of characters, concat over a list of strings. Built once, in two
||| walks of the list, the first for its size; folded from a constant list
||| by the runtime's cons and append. No runtime function of its own: its
||| lowering is the walk.
public export
listBuilder : Mnemonic -> TypeC -> Doc -> Op 1 1 0 0
listBuilder m list d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = [single "list" list]
  , outs = [result "result" strValue]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = builds 0 Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = d
  }

||| How many scalar values an element of a list is: one each, as every
||| character is, or as many as an op of the runtime counts of it, as a
||| string's length does.
public export
data ElementScalars = OneEach | CountedBy OpRef

||| An element's scalar values as its table holds them: the count, or the
||| op whose runtime function counts them.
scalarsConstant : ElementScalars -> Constant
scalarsConstant OneEach = IntConstant 1
scalarsConstant (CountedBy m) = OpEntry m

||| What a builder of a string of a list does with each element
||| (`ListElement<Op>`), its lowering's one table: where the string is made
||| only to be written, each element is written as the op that writes one
||| writes it (`output`); otherwise the first walk adds up each element's
||| bytes, as the op that measures one does (`bytes`), and its scalar
||| values (`scalars`), and the second writes it into the string being
||| built, giving the next offset (`into`).
listElement : (output, bytes : OpRef) -> ElementScalars -> (into : RuntimeHelper) -> Specialized
listElement output bytes scalars into = MkSpecialized "ListElement"
  [ ("output", OpEntry output), ("bytes", OpEntry bytes), ("scalars", scalarsConstant scalars)
  , ("into", HelperConstant into) ]

||| A character is written as io.put_char writes one, is as many bytes as
||| str.scalar_bytes says, and is one scalar value.
public export
strPack : Op 1 1 0 0
strPack =
  { specializations := [listElement putCharOp.mnemonic strScalarBytes.mnemonic OneEach strPutChar]
  , members := [compositeMeaning "::idr::StrPackOp"] }
  (listBuilder "str.pack" (SatisfiesType charListP) (says "the string of a list of characters, built once"))

||| A string is written as io.put_str writes one, and is as many bytes and
||| scalar values as str.bytes_length and str.length say.
public export
strConcat : Op 1 1 0 0
strConcat =
  { specializations := [listElement putStrOp.mnemonic strBytesLength.mnemonic (CountedBy strLength.mnemonic) strPutStr]
  , members := [compositeMeaning "::idr::StrConcatOp"] }
  (listBuilder "str.concat" (SatisfiesType strListP) (says "the concatenation of a list of strings, built once"))

public export
stringOps : List AnyOp
stringOps =
  [ SomeOp strAppend, SomeOp strCons, SomeOp strFromChar, SomeOp strShowSint
  , SomeOp strShowUint, SomeOp strShowDouble, SomeOp strSubstr, SomeOp strReverse
  , SomeOp strDropBytes, SomeOp strTail, SomeOp strPack, SomeOp strConcat
  , SomeOp strLength, SomeOp strBytesLength, SomeOp strScalarAt, SomeOp strScalarBytes
  , SomeOp strIndex, SomeOp strHead, SomeOp strCmp, SomeOp strToInt, SomeOp strToDouble ]
