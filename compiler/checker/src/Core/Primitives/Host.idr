-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
-- Copyright (c) 2026 Bjorn Pagen
||| What the hosts that run the checker give their primitives and no proof
||| can follow, stated once, here. Two hosts run it: Chez Scheme, under stock
||| Idris, and idris-mlir's own code. A primitive does not reduce at a
||| variable, so what it computes is a fact of each host and of no
||| definition; and some primitives are declared partial, defined on values
||| a test the host's types cannot carry picks out. Each fact below is one
||| primitive's (or one comparison's), with the reason both hosts keep it.
||| The checker's other trusts, of its evaluator and its context, are
||| `Idris.Host`'s; that module imports this one, which imports nothing of
||| the checker, so `Core.Primitives` reaches these facts too.
module Core.Primitives.Host

%default total

-- The trust, at quantity 0, so it costs nothing when the checker runs. It
-- is applied only to the comparisons below, whose truth is the host's.
0 trusted : a
trusted = believe_me ()

------------------------------------------------------------------------------
-- Comparisons
------------------------------------------------------------------------------

-- Idris's equality of names compares an identifier's index, a machine
-- name's number, a resolved name's index and the like as the runtime's
-- integers, by `prim__eq_Int`, which a proof cannot evaluate at a
-- variable. That it is true of an integer and itself, and only of an
-- integer and itself, are facts of each host that runs this compiler and
-- of no definition: Chez compares two exact integers by `=`, and
-- idris-mlir two 64-bit words by `arith.cmpi eq`, each true exactly when
-- the two are one integer. Its symmetry follows from the two.
export
0 intEqualityReflexive : (x : Int) -> (x == x) = True
intEqualityReflexive _ = trusted

export
0 intEqualitySound : (x, y : Int) -> (x == y) = True -> x = y
intEqualitySound _ _ _ = trusted

-- A character is compared by `prim__eq_Char`: Chez's `char=?`, and
-- idris-mlir's `arith.cmpi eq` of the two code points, each true exactly
-- when the two are one character. It is trusted itself rather than through
-- `ord` and the comparison of integers, which would trust two facts of the
-- runtime in its place: that `prim__eq_Char` agrees with `prim__eq_Int` on
-- code points, and that `prim__cast_CharInt` gives two characters two code
-- points.
export
0 charEqualitySound : (x, y : Char) -> (x == y) = True -> x = y
charEqualitySound _ _ _ = trusted

-- A string is compared by `prim__eq_String`: Chez's `string=?`, character
-- by character, and idris-mlir's runtime, which compares the two UTF-8
-- encodings byte by byte and their lengths, each true exactly when the two
-- are one string.
export
0 stringEqualitySound : (x, y : String) -> (x == y) = True -> x = y
stringEqualitySound _ _ _ = trusted

------------------------------------------------------------------------------
-- Partial primitives
------------------------------------------------------------------------------

-- Each function below tests what makes its primitive partial, of values the
-- program being checked holds and so known only when the checker runs, and
-- calls the primitive only where the test passes. That the primitive then
-- returns is the host's fact, trusted at that call, since the host gives
-- the primitive no type that could carry the test's evidence.

-- The head, the tail and an index of a string are declared partial outside
-- the string alone: an empty string has no head or tail, and an index names
-- a character only within it. Chez reads them with `string-ref` and
-- `substring`, which fail only there, and idris-mlir's runtime reads them
-- once its lowering has made the same test.
export
stringHead : String -> Maybe Char
stringHead "" = Nothing
stringHead str = Just (assert_total (prim__strHead str))

export
stringTail : String -> Maybe String
stringTail "" = Nothing
stringTail str = Just (assert_total (prim__strTail str))

export
stringIndex : String -> Int -> Maybe Char
stringIndex str i
    = if i >= 0 && integerToNat (cast i) < length str
         then Just (assert_total (prim__strIndex str i))
         else Nothing

-- Integer division and remainder are declared partial for a zero divisor
-- alone. Chez computes both from `quotient` and `remainder`, which fail
-- only there, and idris-mlir's Euclidean division and remainder are defined
-- by every divisor that is not zero.
export
divInteger : Integer -> Integer -> Maybe Integer
divInteger _ 0 = Nothing
divInteger x y = Just (assert_total (prim__div_Integer x y))

export
divInt : Int -> Int -> Maybe Int
divInt _ 0 = Nothing
divInt x y = Just (assert_total (prim__div_Int x y))

export
divInt8 : Int8 -> Int8 -> Maybe Int8
divInt8 _ 0 = Nothing
divInt8 x y = Just (assert_total (prim__div_Int8 x y))

export
divInt16 : Int16 -> Int16 -> Maybe Int16
divInt16 _ 0 = Nothing
divInt16 x y = Just (assert_total (prim__div_Int16 x y))

export
divInt32 : Int32 -> Int32 -> Maybe Int32
divInt32 _ 0 = Nothing
divInt32 x y = Just (assert_total (prim__div_Int32 x y))

export
divInt64 : Int64 -> Int64 -> Maybe Int64
divInt64 _ 0 = Nothing
divInt64 x y = Just (assert_total (prim__div_Int64 x y))

export
divBits8 : Bits8 -> Bits8 -> Maybe Bits8
divBits8 _ 0 = Nothing
divBits8 x y = Just (assert_total (prim__div_Bits8 x y))

export
divBits16 : Bits16 -> Bits16 -> Maybe Bits16
divBits16 _ 0 = Nothing
divBits16 x y = Just (assert_total (prim__div_Bits16 x y))

export
divBits32 : Bits32 -> Bits32 -> Maybe Bits32
divBits32 _ 0 = Nothing
divBits32 x y = Just (assert_total (prim__div_Bits32 x y))

export
divBits64 : Bits64 -> Bits64 -> Maybe Bits64
divBits64 _ 0 = Nothing
divBits64 x y = Just (assert_total (prim__div_Bits64 x y))

export
modInteger : Integer -> Integer -> Maybe Integer
modInteger _ 0 = Nothing
modInteger x y = Just (assert_total (prim__mod_Integer x y))

export
modInt : Int -> Int -> Maybe Int
modInt _ 0 = Nothing
modInt x y = Just (assert_total (prim__mod_Int x y))

export
modInt8 : Int8 -> Int8 -> Maybe Int8
modInt8 _ 0 = Nothing
modInt8 x y = Just (assert_total (prim__mod_Int8 x y))

export
modInt16 : Int16 -> Int16 -> Maybe Int16
modInt16 _ 0 = Nothing
modInt16 x y = Just (assert_total (prim__mod_Int16 x y))

export
modInt32 : Int32 -> Int32 -> Maybe Int32
modInt32 _ 0 = Nothing
modInt32 x y = Just (assert_total (prim__mod_Int32 x y))

export
modInt64 : Int64 -> Int64 -> Maybe Int64
modInt64 _ 0 = Nothing
modInt64 x y = Just (assert_total (prim__mod_Int64 x y))

export
modBits8 : Bits8 -> Bits8 -> Maybe Bits8
modBits8 _ 0 = Nothing
modBits8 x y = Just (assert_total (prim__mod_Bits8 x y))

export
modBits16 : Bits16 -> Bits16 -> Maybe Bits16
modBits16 _ 0 = Nothing
modBits16 x y = Just (assert_total (prim__mod_Bits16 x y))

export
modBits32 : Bits32 -> Bits32 -> Maybe Bits32
modBits32 _ 0 = Nothing
modBits32 x y = Just (assert_total (prim__mod_Bits32 x y))

export
modBits64 : Bits64 -> Bits64 -> Maybe Bits64
modBits64 _ 0 = Nothing
modBits64 x y = Just (assert_total (prim__mod_Bits64 x y))
