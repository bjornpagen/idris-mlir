-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a key writes of a literal: a constant's symbols, which the key's
||| writer writes (`Keys.write`) and a template weighs as written
||| (`Readings.constant`), and the shape of a run of successors, which the
||| key writes a node per constructor of and a template reads as its
||| height. Both readers take them from here, below the readings an
||| instance is keyed by, so the two read one writing.
module IdrisMLIR.Frontend.Translate.Literals

import Core.TT

import IdrisMLIR.Proof.Forms

%default total

||| A chain of data constructors each applied to the next, n of them,
||| ending in one applied to nothing: the shape of a run of successors down
||| to a zero, which the key writes a node per constructor of
||| (`keyTree`), whatever roles the constructors have.
public export
data Run : Term vs -> Nat -> Type where
  RunZero : Run (Ref fc (DataCon tag arity) z) 0
  RunSucc : Run a k -> Run (App fc (Ref rfc (DataCon tag arity) s) a) (S k)

||| A primitive type by its number.
export
primitive : PrimType -> Fin 14
primitive IntType = 0
primitive Int8Type = 1
primitive Int16Type = 2
primitive Int32Type = 3
primitive Int64Type = 4
primitive IntegerType = 5
primitive Bits8Type = 6
primitive Bits16Type = 7
primitive Bits32Type = 8
primitive Bits64Type = 9
primitive StringType = 10
primitive CharType = 11
primitive DoubleType = 12
primitive WorldType = 13

public export
node : Form -> Token Form
node f = Node f Nothing 0

export
glyphOf : Char -> Glyph
glyphOf c = let k = cast {to = Integer} (ord c) in (lowBits 11 (k `div` 1024), lowBits 10 k)

export
spellChars : List Char -> List (Token Form)
spellChars [] = []
spellChars (c :: cs) = node (Spelt (glyphOf c)) :: spellChars cs

export
spell : String -> List (Token Form)
spell s = spellChars (unpack s)

||| An integer constant's one token: its type, sign and magnitude. Its body
||| is public, as `writeConstant`'s is, so that what a proof states of a
||| constant's key reduces through it to the magnitude.
public export
integer : PrimType -> Integer -> List (Token Form)
integer t v = [Number (IntegerLit (primitive t) (v < 0)) (integerToNat (abs v))]

||| A constant: an integer by its type, sign and magnitude, a string and a
||| double by their characters (a double's print tells doubles apart), a
||| character, a primitive type, the world.
public export
writeConstant : Constant -> List (Token Form)
writeConstant (I x) = integer IntType (cast x)
writeConstant (I8 x) = integer Int8Type (cast x)
writeConstant (I16 x) = integer Int16Type (cast x)
writeConstant (I32 x) = integer Int32Type (cast x)
writeConstant (I64 x) = integer Int64Type (cast x)
writeConstant (BI x) = integer IntegerType x
writeConstant (B8 x) = integer Bits8Type (cast x)
writeConstant (B16 x) = integer Bits16Type (cast x)
writeConstant (B32 x) = integer Bits32Type (cast x)
writeConstant (B64 x) = integer Bits64Type (cast x)
writeConstant (Str x) = node (Shaped Text) :: spell x
writeConstant (Ch x) = [node (Character (glyphOf x))]
writeConstant (Db x) = node (Shaped Floating) :: spell (show x)
writeConstant (PrT t) = [node (PrimitiveType (primitive t))]
writeConstant WorldVal = [node (Shaped World)]
