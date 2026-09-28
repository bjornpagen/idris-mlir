||| Category 1 of the registry: Idris's own
||| backend contract, which the compiler must implement. None of it is
||| privileged knowledge: Idris requires it of every backend.
|||
||| - The entry convention: the root of a program, and its main module.
||| - The IO primitives the libraries declare for backends, keyed by their
|||   `%foreign` spec (their Idris name and type are the shape validated).
||| - Idris's builtins (`PrimFn`) are a closed type the frontend matches on
|||   directly (`Frontend.Translate.primitive`), so they have no entries.
module IdrisMLIR.Registry.Primitives

import IdrisMLIR.Registry.Entry
import IdrisMLIR.Registry.Name
import IdrisMLIR.Rule
import IdrisMLIR.Types

%default total

||| The root of a `main : Int` program is `main` in its module,
||| given by its path, outermost first.
export
intEntry : List String -> QName
intEntry ns = MkQName ns "main"

||| The module Idris takes `main` from when none is named.
export
mainModule : List String
mainModule = ["Main"]

------------------------------------------------------------------------------
-- Shapes of the IO contract
------------------------------------------------------------------------------

world : Shape
world = Prim WorldP

unit : Shape
unit = Head (Def (MkQName ["Builtin"] "Unit")) []

ioRes : Shape -> Shape
ioRes a = Head (Def (MkQName ["PrimIO"] "IORes")) [a]

io : Shape -> Shape
io a = Head (Def (MkQName ["PrimIO"] "IO")) [a]

------------------------------------------------------------------------------
-- The table
------------------------------------------------------------------------------

||| `unsafePerformIO : {0 a : Type} -> IO a -> a`: Idris hands an IO backend
||| `unsafePerformIO main`.
programRoot : Entry
programRoot = MkEntry (Def (MkQName ["PrimIO"] "unsafePerformIO"))
                      (Typed (Pi Q0 TypeOfTypes (Pi QW (io Hole) Hole)))
                      ProgramRoot [FeEntry4]

||| An IO primitive of `Prelude.IO`, by its spec, with the name that
||| declares it and its type.
ioPrimitive : Spec -> String -> Shape -> IOOp -> Entry
ioPrimitive spec name shape op =
  MkEntry (Foreign spec) (Declared (MkQName ["Prelude", "IO"] name) shape) (IOCall op) [ProfIO4]

||| The table: Idris's backend contract as the compiler implements it.
export
primitives : List Entry
primitives =
  [ programRoot
  , ioPrimitive (MkSpec "C" "idris2_putStr") "prim__putStr"
                (Pi QW (Prim StringP) (Pi Q1 world (ioRes unit))) PutStr
  , ioPrimitive (MkSpec "C" "putchar") "prim__putChar"
                (Pi QW (Prim CharP) (Pi Q1 world (ioRes unit))) PutChar
  -- The Prelude's getChar reads one byte.
  , ioPrimitive (MkSpec "C" "getchar") "prim__getChar"
                (Pi Q1 world (ioRes (Prim CharP))) GetByte ]
