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

||| The table.
export
recognized : List Entry
recognized =
  [ identity "replace"
  , identity "rewrite__impl"
  , rootOnly "unsafePerformIO" (Pi Q0 TypeOfTypes (Pi QW (Head (Def (MkQName ["PrimIO"] "IO")) [Hole]) Hole))
  , rootOnly "unsafeCreateWorld" (Pi Q0 TypeOfTypes (Pi Q1 (Pi Q1 (Prim WorldP) Hole) Hole))
  , rootOnly "unsafeDestroyWorld" (Pi Q0 TypeOfTypes (Pi Q1 (Prim WorldP) (Pi QW Hole Hole)))
  , spelling "prim__believe_me"
  , spelling "prim__crash"
  , spelling "believe_me"
  , spelling "idris_crash" ]
