-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
-- Copyright (c) 2026 Bjorn Pagen
||| What the checker takes from the primitives of the hosts that run it,
||| where a primitive is partial or a number is too large for a type, stated
||| once, here. Two hosts run it: Chez Scheme, under stock Idris, and
||| idris-mlir's own code. A primitive declared partial (a string's head, a
||| division) is reached through the prelude's own total function or method,
||| which returns nothing where the primitive is undefined, so the checker
||| asserts nothing of it. The numbers a type must not build in unary are
||| held here by name, with what a proof reads of them.
module Core.Primitives.Host

import Data.Nat

%default total

------------------------------------------------------------------------------
-- Numbers held by name
------------------------------------------------------------------------------

-- The type checker computes naturals in unary, so a type that held two to
-- 32 or to 1024 would build that number wherever the type is normalised or
-- compared, past what a type check affords. Each is exported by name alone:
-- it unfolds nowhere outside this module, so it is stuck in every type
-- there. A program computes either as any other number.

||| 1024: neither a character's code nor a finite double's integer part
||| reaches two to it on either host, a double's largest finite value being
||| below 2^1024. It is the widest exponent of what one primitive computes
||| from literals, which the frontend's bound on a computed literal names.
export
widestExponent : Nat
widestExponent = 1024

||| 2^32: the ratio of one limb's weight to the next in a TTC's integer
||| (`Core.Binary.Prims`).
export
limbBase : Nat
limbBase = 4294967296

||| The limbs' ratio is at least two, so their weights grow.
export
0 limbBaseAbove : LTE 2 Host.limbBase
limbBaseAbove = LTESucc (LTESucc LTEZero)

------------------------------------------------------------------------------
-- Partial primitives
------------------------------------------------------------------------------

-- Each function below gives nothing where its primitive is undefined, of
-- values the program being checked holds and so known only when the
-- checker runs. Each reaches the primitive through the prelude: a string's
-- head and tail through `strUncons`, its character at an index through the
-- total `prim__strSubstr` and `strUncons`, a division and a remainder
-- through `Integral`'s `div` and `mod`, each defined at every divisor but
-- zero. The primitive's partiality is the prelude's, stated once there for
-- both hosts.

-- An empty string has no head or tail, and an index names a character only
-- within the string.
export
stringHead : String -> Maybe Char
stringHead str = map fst (strUncons str)

export
stringTail : String -> Maybe String
stringTail str = map snd (strUncons str)

export
stringIndex : String -> Int -> Maybe Char
stringIndex str i
    = if i >= 0 && integerToNat (cast i) < length str
         then map fst (strUncons (prim__strSubstr i 1 str))
         else Nothing

-- Integer division and remainder are undefined at a zero divisor alone.
export
divInteger : Integer -> Integer -> Maybe Integer
divInteger _ 0 = Nothing
divInteger x y = Just (div x y)

export
divInt : Int -> Int -> Maybe Int
divInt _ 0 = Nothing
divInt x y = Just (div x y)

export
divInt8 : Int8 -> Int8 -> Maybe Int8
divInt8 _ 0 = Nothing
divInt8 x y = Just (div x y)

export
divInt16 : Int16 -> Int16 -> Maybe Int16
divInt16 _ 0 = Nothing
divInt16 x y = Just (div x y)

export
divInt32 : Int32 -> Int32 -> Maybe Int32
divInt32 _ 0 = Nothing
divInt32 x y = Just (div x y)

export
divInt64 : Int64 -> Int64 -> Maybe Int64
divInt64 _ 0 = Nothing
divInt64 x y = Just (div x y)

export
divBits8 : Bits8 -> Bits8 -> Maybe Bits8
divBits8 _ 0 = Nothing
divBits8 x y = Just (div x y)

export
divBits16 : Bits16 -> Bits16 -> Maybe Bits16
divBits16 _ 0 = Nothing
divBits16 x y = Just (div x y)

export
divBits32 : Bits32 -> Bits32 -> Maybe Bits32
divBits32 _ 0 = Nothing
divBits32 x y = Just (div x y)

export
divBits64 : Bits64 -> Bits64 -> Maybe Bits64
divBits64 _ 0 = Nothing
divBits64 x y = Just (div x y)

export
modInteger : Integer -> Integer -> Maybe Integer
modInteger _ 0 = Nothing
modInteger x y = Just (mod x y)

export
modInt : Int -> Int -> Maybe Int
modInt _ 0 = Nothing
modInt x y = Just (mod x y)

export
modInt8 : Int8 -> Int8 -> Maybe Int8
modInt8 _ 0 = Nothing
modInt8 x y = Just (mod x y)

export
modInt16 : Int16 -> Int16 -> Maybe Int16
modInt16 _ 0 = Nothing
modInt16 x y = Just (mod x y)

export
modInt32 : Int32 -> Int32 -> Maybe Int32
modInt32 _ 0 = Nothing
modInt32 x y = Just (mod x y)

export
modInt64 : Int64 -> Int64 -> Maybe Int64
modInt64 _ 0 = Nothing
modInt64 x y = Just (mod x y)

export
modBits8 : Bits8 -> Bits8 -> Maybe Bits8
modBits8 _ 0 = Nothing
modBits8 x y = Just (mod x y)

export
modBits16 : Bits16 -> Bits16 -> Maybe Bits16
modBits16 _ 0 = Nothing
modBits16 x y = Just (mod x y)

export
modBits32 : Bits32 -> Bits32 -> Maybe Bits32
modBits32 _ 0 = Nothing
modBits32 x y = Just (mod x y)

export
modBits64 : Bits64 -> Bits64 -> Maybe Bits64
modBits64 _ 0 = Nothing
modBits64 x y = Just (mod x y)
