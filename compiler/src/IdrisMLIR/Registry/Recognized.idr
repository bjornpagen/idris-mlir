||| Category 2 of the registry: ordinary
||| library definitions the compiler treats specially. This is the
||| privileged-knowledge table: each entry makes its definition faster or
||| stricter, never different, and removing one may change speed or which
||| programs are rejected, never a program's result.
module IdrisMLIR.Registry.Recognized

import IdrisMLIR.Registry.Entry
import IdrisMLIR.Registry.Name
import IdrisMLIR.Rule
import IdrisMLIR.Types

%default total

||| `Builtin.Equal` applied to its two types and two sides, which is what
||| `x = y` and `x === y` normalise to.
equal : Shape
equal = Head (Def (MkQName ["Builtin"] "Equal")) [Hole, Hole, Hole, Hole]

||| A rewriting combinator: a type, two erased values and an erased
||| predicate, an erased proof that the values are equal, and the value to
||| rewrite, the one runtime argument, which it returns.
rewriting : Shape
rewriting = Pi Q0 TypeOfTypes (Pi Q0 Hole (Pi Q0 Hole (Pi Q0 Hole (Pi Q0 equal (Pi Q1 Hole Hole)))))

||| `replace` and `rewrite__impl`, which `rewrite` elaborates to.
identity : String -> Entry
identity name = MkEntry (Def (MkQName ["Builtin"] name)) (Typed rewriting) IdentityOnLastArgument [IdentityHook]

||| A world operation of `PrimIO`, reachable only through the program root.
rootOnly : String -> Shape -> Entry
rootOnly name shape = MkEntry (Def (MkQName ["PrimIO"] name)) (Typed shape) (Forbidden WorldUse) [WorldUse]

||| An escape hatch as the user can write it. Idris evaluates
||| `prim__believe_me` applied to a constructor while elaborating, so it can
||| vanish from TT; the source is scanned instead.
spelling : String -> Entry
spelling s = MkEntry (Spelling s) Written (Forbidden EscapeHatch) [EscapeHatch]

------------------------------------------------------------------------------
-- Naturals
------------------------------------------------------------------------------

nat : Shape
nat = Head (Def (MkQName ["Prelude", "Types"] "Nat")) []

bool : Shape
bool = Head (Def (MkQName ["Prelude", "Basics"] "Bool")) []

binary : Shape -> Shape
binary result = Pi QW nat (Pi QW nat result)

||| The library function that makes a `Bool` of an `Int`.
intToBool : QName
intToBool = MkQName ["Prelude", "Basics"] "intToBool"

||| A function on naturals, at its name in `ns`, and what it means. These
||| are the functions Idris's own backends compute on the representation of
||| `Nat` instead of by their unary recursions (the Prelude's `natHack`), and
||| `Data.Nat`'s tests, which are `compareNat` in another form.
natural : List String -> String -> Shape -> NatMeaning -> Entry
natural ns name shape m = MkEntry (Def (MkQName ns name)) (Typed shape) (NatOperation m) [HookShape]

||| The functions on naturals.
naturals : List Entry
naturals =
  [ natural types "natToInteger" (Pi QW nat (Prim IntegerP)) (Primitive NatToBig)
  , natural types "integerToNat" (Pi QW (Prim IntegerP) nat) (Primitive NatFromBig)
  , natural types "prim__integerToNat" (Pi QW (Prim IntegerP) nat) (Primitive NatFromBig)
  , natural types "plus" (binary nat) (Primitive NatAdd)
  , natural types "mult" (binary nat) (Primitive NatMul)
  , natural types "minus" (binary nat) (Clamped (BigArith Sub))
  , natural types "equalNat" (binary bool) (Tested CEq intToBool)
  , natural types "compareNat" (binary (Head (Def (MkQName ["Prelude", "EqOrd"] "Ordering")) []))
            (OnIntegers (MkQName ["Prelude", "EqOrd"] "compareInteger"))
  , natural ["Data", "Nat"] "lte" (binary bool) (Tested CLte intToBool)
  , natural ["Data", "Nat"] "gte" (binary bool) (Tested CGte intToBool)
  , natural ["Data", "Nat"] "lt" (binary bool) (Tested CLt intToBool)
  , natural ["Data", "Nat"] "gt" (binary bool) (Tested CGt intToBool) ]
  where
    types : List String
    types = ["Prelude", "Types"]

||| The table.
export
recognized : List Entry
recognized =
  naturals ++
  [ identity "replace"
  , identity "rewrite__impl"
  , rootOnly "unsafePerformIO" (Pi Q0 TypeOfTypes (Pi QW (Head (Def (MkQName ["PrimIO"] "IO")) [Hole]) Hole))
  , rootOnly "unsafeCreateWorld" (Pi Q0 TypeOfTypes (Pi Q1 (Pi Q1 (Prim WorldP) Hole) Hole))
  , rootOnly "unsafeDestroyWorld" (Pi Q0 TypeOfTypes (Pi Q1 (Prim WorldP) (Pi QW Hole Hole)))
  , spelling "prim__believe_me"
  , spelling "prim__crash"
  , spelling "believe_me"
  , spelling "idris_crash" ]
