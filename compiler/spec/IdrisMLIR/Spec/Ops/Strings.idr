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
import IdrisMLIR.Spec.Ops.Checks
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

||| A builder of a new string by the runtime's function `stem`, its operands
||| as the function takes them.
public export
builder : {i : Nat} -> (m : Mnemonic) -> (ins : Vect i Operand) -> RuntimeCall i 1 -> List (Trait i 1)
       -> Doc
       -> {auto 0 named : So (distinct (groupNames ins [result "result" Shapes.strValue] [] []))}
       -> Op i 1 0 0
builder m ins call traits d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = ins
  , outs = [result "result" strValue]
  , attrs = []
  , regions = []
  , traits = traits
  , interfaces = []
  , effects = builds 0 Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime call
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
  (builder "str.append" [single "lhs" strRead, single "rhs" strRead]
    (MkRuntimeCall "str_append" [TakesStr, TakesStr] (Returns GivesStr)) []
    (says "the concatenation of two strings"))

public export
strCons : Op 2 1 0 0
strCons = builder "str.cons" [single "head" i32, single "tail" strRead]
  (MkRuntimeCall "str_cons" [TakesInt32, TakesStr] (Returns GivesStr)) [OurTrait neverEmpty]
  (says "a character before a string")

public export
strFromChar : Op 1 1 0 0
strFromChar = builder "str.from_char" [single "value" i32]
  (MkRuntimeCall "str_from_char" [TakesInt32] (Returns GivesStr)) [OurTrait neverEmpty]
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
writerOf : Ident -> Symbol -> RuntimeCall 1 1 -> Line -> RuntimeHelper
writerOf name sym shown doc = MkRuntimeHelper name sym [(head shown.takes, "value")] HelperNothing doc

||| A show whose text an output of it alone writes with the show's writer
||| (`ShownOutput<Op>`): what the lowering emits for a string the show makes
||| only to write, so `print` of a number builds no string.
public export
shownOutput : RuntimeHelper -> Specialized
shownOutput writer = MkSpecialized "ShownOutput" [("writer", HelperConstant writer)]

showSigned : RuntimeCall 1 1
showSigned = MkRuntimeCall "str_show_s" [TakesSigned] (Returns GivesStr)

showUnsigned : RuntimeCall 1 1
showUnsigned = MkRuntimeCall "str_show_u" [TakesUnsigned] (Returns GivesStr)

showDouble : RuntimeCall 1 1
showDouble = MkRuntimeCall "str_show_f64" [TakesDouble] (Returns GivesStr)

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
  (builder "str.show_sint" [single "value" int] showSigned [OurTrait neverEmpty]
    (says "the decimal text of a signed integer"))

public export
strShowUint : Op 1 1 0 0
strShowUint =
  { specializations := [shownOutput putUnsigned] }
  (builder "str.show_uint" [single "value" int] showUnsigned [OurTrait neverEmpty]
    (says "the decimal text of an unsigned integer"))

public export
strShowDouble : Op 1 1 0 0
strShowDouble =
  { specializations := [shownOutput putDouble] }
  (builder "str.show_double" [single "value" f64] showDouble [OurTrait neverEmpty]
    (says "the text of a Double, as prim__cast_DoubleString writes it"))

------------------------------------------------------------------------------
-- Other builders
------------------------------------------------------------------------------

public export
strSubstr : Op 3 1 0 0
strSubstr = builder "str.substr" [single "str" strRead, single "start" i64, single "length" i64]
  (MkRuntimeCall "str_substr" [TakesStr, TakesInt64, TakesInt64] (Returns GivesStr)) []
  (says "the characters of a string from a start, at most a length")

public export
strReverse : Op 1 1 0 0
strReverse = builder "str.reverse" [single "str" strRead]
  (MkRuntimeCall "str_reverse" [TakesStr] (Returns GivesStr)) []
  (says "the characters of a string in reverse order")

||| A string by byte offset, as the linear string iterator walks it: every
||| offset has a meaning, the runtime's, so no guard.
public export
strDropBytes : Op 2 1 0 0
strDropBytes = builder "str.drop_bytes" [single "str" strRead, single "offset" i64]
  (MkRuntimeCall "str_drop_bytes" [TakesStr, TakesInt64] (Returns GivesStr)) []
  (says "the characters of a string from a byte offset on")

||| A string without its first character, of a string that is not empty,
||| which `idr.check.nonempty` guards.
public export
strTail : Op 1 1 0 0
strTail =
  { guards := [MkGuard nonemptyOp [0] TailOfEmptyString]
  , speculation := Conditionally }
  (builder "str.tail" [single "str" strRead]
    (MkRuntimeCall "str_tail" [TakesStr] (Returns GivesStr)) []
    (says "a string without its first character, of a string that is not empty"))

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

public export
strPack : Op 1 1 0 0
strPack = listBuilder "str.pack" (SatisfiesType charListP) (says "the string of a list of characters, built once")

public export
strConcat : Op 1 1 0 0
strConcat = listBuilder "str.concat" (SatisfiesType strListP) (says "the concatenation of a list of strings, built once")

------------------------------------------------------------------------------
-- What a string gives
------------------------------------------------------------------------------

||| A runtime function of a string that gives no new string, its result's
||| type the one its constraint fixes.
public export
reader : {i : Nat} -> (m : Mnemonic) -> (ins : Vect i Operand) -> (res : Result) -> RuntimeCall i 1
      -> List InterfaceUse -> Doc
      -> {auto 0 named : So (distinct (groupNames ins [res] [] []))}
      -> Op i 1 0 0
reader m ins res call ifaces d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = ins
  , outs = [res]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = ifaces
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime call
  , verify = DeclarationOnly
  , format = plain i
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = d
  , typing = fixedTypes [res]
  }

ranges : InterfaceUse
ranges = Declares InferIntRange ["inferResultRanges"]

public export
strLength : Op 1 1 0 0
strLength = reader "str.length" [single "str" strRead] (result "result" i64)
  (MkRuntimeCall "str_length" [TakesStr] (Returns GivesInt64)) [ranges]
  (says "the number of characters of a string")

||| The length of a string's UTF-8, interior zeros included.
public export
strBytesLength : Op 1 1 0 0
strBytesLength = reader "str.bytes_length" [single "str" strRead] (result "result" i64)
  (MkRuntimeCall "str_bytes_length" [TakesStr] (Returns GivesInt64)) []
  (says "the number of bytes of a string")

public export
strScalarAt : Op 2 1 0 0
strScalarAt = reader "str.scalar_at" [single "str" strRead, single "offset" i64] (result "result" i32)
  (MkRuntimeCall "str_scalar_at" [TakesStr, TakesInt64] (Returns GivesInt32)) [ranges]
  (says "the character that starts at a byte offset, 0 at the end")

||| The iterator's step past a character it read: the length of its UTF-8,
||| the runtime's one rule, which the string's encoding is.
public export
strScalarBytes : Op 1 1 0 0
strScalarBytes = reader "str.scalar_bytes" [single "value" i32] (result "result" i64)
  (MkRuntimeCall "str_scalar_bytes" [TakesInt32] (Returns GivesInt64)) [ranges]
  (says "the number of bytes of a character's UTF-8")

||| The character at an index of the string, which `idr.check.in_bounds`
||| guards against this very string.
public export
strIndex : Op 2 1 0 0
strIndex =
  { guards := [MkGuard inBoundsOp [1, 0] StringIndexOutOfRange]
  , speculation := Conditionally }
  (reader "str.index" [single "str" strRead, single "index" i64] (result "result" i32)
    (MkRuntimeCall "str_index" [TakesStr, TakesInt64] (Returns GivesInt32)) []
    (says "the character at an index within the string"))

||| The first character of a string that is not empty, which
||| `idr.check.nonempty` guards.
public export
strHead : Op 1 1 0 0
strHead =
  { guards := [MkGuard nonemptyOp [0] HeadOfEmptyString]
  , speculation := Conditionally }
  (reader "str.head" [single "str" strRead] (result "result" i32)
    (MkRuntimeCall "str_head" [TakesStr] (Returns GivesInt32)) []
    (says "the first character of a string that is not empty"))

public export
strCmp : Op 2 1 1 0
strCmp = MkOp
  { home = InIdr
  , mnemonic = "str.cmp"
  , ins = [single "lhs" strRead, single "rhs" strRead]
  , outs = made
  , attrs = [property "predicate" (EnumProperty comparisonEnum)]
  , regions = []
  , traits = []
  , interfaces = []
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "str_cmp" [TakesStr, TakesStr] (Returns GivesOrder))
  , verify = DeclarationOnly
  , format = attrFirst 2 0
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "compares two strings"
  , typing = fixedTypes made
  }
  where
    made : Vect 1 Result
    made = [result "result" i1]

||| One op for IntN and BitsN: the runtime's reading of a string has no
||| signedness, and the op wraps what it gives to its width.
public export
strToInt : Op 1 1 0 0
strToInt = reader "str.to_int" [single "str" strRead] (result "result" int)
  (MkRuntimeCall "str_to_int" [TakesStr] (Returns GivesWrapped)) []
  (says "a string as an integer, as prim__cast_StringT reads it")

public export
strToDouble : Op 1 1 0 0
strToDouble = reader "str.to_double" [single "str" strRead] (result "result" f64)
  (MkRuntimeCall "str_to_double" [TakesStr] (Returns GivesDouble)) []
  (says "a string as a Double, as prim__cast_StringDouble reads it")

public export
stringOps : List AnyOp
stringOps =
  [ SomeOp strAppend, SomeOp strCons, SomeOp strFromChar, SomeOp strShowSint
  , SomeOp strShowUint, SomeOp strShowDouble, SomeOp strSubstr, SomeOp strReverse
  , SomeOp strDropBytes, SomeOp strTail, SomeOp strPack, SomeOp strConcat
  , SomeOp strLength, SomeOp strBytesLength, SomeOp strScalarAt, SomeOp strScalarBytes
  , SomeOp strIndex, SomeOp strHead, SomeOp strCmp, SomeOp strToInt, SomeOp strToDouble ]
