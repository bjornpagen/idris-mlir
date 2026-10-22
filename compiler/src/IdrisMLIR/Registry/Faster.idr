-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The registry's faster entries: each lowers a definition whose body is
||| its one meaning to another form of the same meaning, so a build of the
||| frontend with this module replaced by one holding none compiles every
||| program from the bodies, and gives each the result the shipped frontend
||| gives it, slower. They live in this module alone for that build.
module IdrisMLIR.Registry.Faster

import IdrisMLIR.Registry.Entry
import IdrisMLIR.Registry.Name
import IdrisMLIR.Registry.Primitives
import IdrisMLIR.Registry.Recognized
import IdrisMLIR.Spec.Families.Ops
import IdrisMLIR.Spec.Ops.Bigs
import IdrisMLIR.Spec.Ops.Strings
import IdrisMLIR.Spec.Ops.Values
import IdrisMLIR.Types

%default total

------------------------------------------------------------------------------
-- Naturals
------------------------------------------------------------------------------

bool : Shape
bool = Head (Def (MkQName ["Prelude", "Basics"] "Bool")) []

binary : Shape -> Shape
binary result = Pi Mw nat (Pi Mw nat result)

||| The library function that makes a `Bool` of an `Int`.
intToBool : QName
intToBool = MkQName ["Prelude", "Basics"] "intToBool"

||| A function on naturals, at its name in `ns`, and what it means. These
||| are the functions Idris's own backends compute on the representation of
||| `Nat` instead of by their unary recursions (the Prelude's `natHack`), and
||| `Data.Nat`'s tests, which are `compareNat` in another form.
natural : List String -> String -> Shape -> NatMeaning -> Entry Faster
natural ns name shape m = MkEntry (Def (MkQName ns name)) (Typed shape) (NatOperation m)

||| The functions on naturals.
naturals : List (Entry Faster)
naturals =
  [ natural types "natToInteger" (Pi Mw nat (Prim IntegerP)) (Primitive (Op natToBig BigT made))
  , natural types "integerToNat" (Pi Mw (Prim IntegerP) nat) (Primitive (Op natFromBig (NatT IOpaque) made))
  , natural types "prim__integerToNat" (Pi Mw (Prim IntegerP) nat) (Primitive (Op natFromBig (NatT IOpaque) made))
  , natural types "plus" (binary nat) (Primitive (Op bigAdd (NatT IOpaque) made))
  , natural types "mult" (binary nat) (Primitive (Op bigMul (NatT IOpaque) made))
  , natural types "minus" (binary nat) (Clamped (Op bigSub BigT made))
  , natural types "equalNat" (binary bool) (Tested Values.Eq intToBool)
  , natural types "compareNat" (binary (Head (Def (MkQName ["Prelude", "EqOrd"] "Ordering")) []))
            (OnIntegers (MkQName ["Prelude", "EqOrd"] "compareInteger"))
  , natural ["Data", "Nat"] "lte" (binary bool) (Tested Values.Lte intToBool)
  , natural ["Data", "Nat"] "gte" (binary bool) (Tested Values.Gte intToBool)
  , natural ["Data", "Nat"] "lt" (binary bool) (Tested Values.Lt intToBool)
  , natural ["Data", "Nat"] "gt" (binary bool) (Tested Values.Gt intToBool) ]
  where
    types : List String
    types = ["Prelude", "Types"]

------------------------------------------------------------------------------
-- The array language
------------------------------------------------------------------------------

||| A function of the generating set that has a body both hosts run, at its
||| type: its op computes what the body does.
computing : List String -> String -> Shape -> ArrayPrim -> Entry Faster
computing ns name shape p = MkEntry (Def (MkQName ns name)) (Typed shape) (Generating p)

||| `Fin n`.
fin : Shape
fin = Head (Def (MkQName ["Data", "Fin"] "Fin")) [Hole]

||| The array language's value type, whose body holds its elements in
||| base's arrays; the functions of its generating set and of its linear
||| arrays that have bodies, whose calls are the tensor operations of their
||| sequential meaning; and base's `natToFinLT` and `finToNat`, the
||| conversions between a natural and a `Fin`, a numeral laid out as a
||| number, with no range check, its bound its type's: a coordinate is its
||| natural, so an index's position reads as the index, and a loop over an
||| array computes on words. A linear array is no value type: it is its
||| family, a cell holding its array, as the growable vector is, so that
||| its grade says what may write it in place. Its operations take the
||| array out of the cell, run on it and build the cell again; `freeze`,
||| whose body does only that, compiles from its body.
arrays : List (Entry Faster)
arrays =
  [ MkEntry (Def (MkQName arrayCore "Array")) (Typed (Pi M0 shapeType (Pi Mw TypeOfTypes TypeOfTypes)))
            ArrayValueType
  , computing arrayCore "shape" (implicits 2 (arg arrayShape extentsShape)) AShape
  , computing arrayCore "tabulate" (implicits 2 (arg extentsShape (arg (arg indexShape Hole) arrayShape))) ATabulate
  , computing arrayCore "!!" (implicits 2 (arg arrayShape (arg indexShape Hole))) AIndex
  , computing arrayCore "foldLast"
              (implicits 4 (arg (arg Hole (arg Hole Hole)) (arg arrayShape (arg arrayShape arrayShape)))) AFoldLast
  , computing arrayCore "reshape" (implicits 3 (arg extentsShape (Pi M0 Hole (arg arrayShape arrayShape)))) AReshape
  , computing larrayCore "read" (implicits 2 (linear larrayShape (arg indexShape Hole))) ARead
  , computing larrayCore "write" (implicits 2 (linear larrayShape (arg indexShape (arg Hole larrayShape)))) AWrite
  , computing larrayCore "thaw" (implicits 3 (arg arrayShape (linear (linear larrayShape Hole) Hole))) AThaw
  , MkEntry (Def (MkQName ["Data", "Fin"] "natToFinLT")) (Typed (arg nat (implicits 2 fin))) (PureCall numeralOfNatOp [])
  , MkEntry (Def (MkQName ["Data", "Fin"] "finToNat")) (Typed (implicits 1 (arg fin nat))) (PureCall numeralToNatOp []) ]

------------------------------------------------------------------------------
-- Lists and strings
------------------------------------------------------------------------------

||| Base's list, a sum whose nil and cons the string builders take apart:
||| its kind is the registry's, never guessed from its shape; its nil and
||| its cons are its constructors of no field and of two. The Prelude's
||| `pack`, strCons by strCons, builds its string once (`idr.str.pack`);
||| the string iterator's step past a character is the byte length of the
||| character's own string, which the op gives without building it.
listsAndStrings : List (Entry Faster)
listsAndStrings =
  [ MkEntry (Def (MkQName ["Prelude", "Basics"] "List")) (Typed (Pi Mw TypeOfTypes TypeOfTypes)) ListType
  , MkEntry (Def (MkQName preludeTypes "pack")) (Typed (Pi Mw (list (Prim CharP)) (Prim StringP))) (Builds strPack)
  , MkEntry (Def (MkQName iteratorModule "scalarBytes")) (Typed (Pi Mw (Prim CharP) int)) (PureCall strScalarBytes []) ]

||| Every faster entry.
export
faster : List (Entry Faster)
faster = naturals ++ arrays ++ listsAndStrings
