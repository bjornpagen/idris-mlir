||| The library table (docs/architecture/17-registry.md): where code comes
||| from, and what each purpose of the compiler makes of each library.
|||
||| It replaces the lists that answered "is this library code?" and the one
||| that admitted definitions by prefix (the census's M1-M3, P1 and P4). Each
||| purpose keeps its list's membership exactly, so where the lists
||| disagreed the cells do: only `Trusted` and `Admitted` cover base,
||| `BreakLast` leaves out the Prelude, and `Admitted` covers `PrimIO` only
||| for what it lists. Unifying them later means editing cells.
module IdrisMLIR.Registry.Libraries

import IdrisMLIR.Registry.Name

%default total

||| The areas of the base library that the profile trusts (PROF-LIB-3), by
||| their top namespace.
public export
data Area = Data | Control | Decidable | Syntax

||| The libraries the compiler knows, by namespace, as every list knew
||| them: `Builtin` and `PrimIO`, the Prelude's modules, and base's trusted
||| areas. A module of another package under `Data`, or a user module named
||| so, is base to the table as it was to the lists (a disagreement with
||| PROF-LIB-3, kept); the table does not know other packages yet.
public export
data Lib = Builtin | PrimIO | Prelude | Base Area

||| Where code comes from. The registry computes it once, when TT is
||| translated, and every location carries it (`Loc`), so no pass reads a
||| namespace. Code in no module (a primitive, a location Idris does not
||| have) is `Generated`.
public export
data Origin = User | Library Lib | Generated

||| What the compiler asks of a library.
public export
data Purpose
  = ||| An IO program may import it, its source is not lexed for pragmas,
    ||| and its definitions must be admitted (PROF-PROG-4, PROF-LIB-3,
    ||| PROF-PRAG-1, PROF-LIB-1).
    Trusted
  | ||| Every definition of it is admitted (PROF-LIB-1).
    Admitted
  | ||| A function of it is chosen as a loop breaker only when its cycle has
    ||| no function from elsewhere (OPT-PIPE-3).
    BreakLast
  | ||| A diagnostic inside it is reported at the user's code that reached
    ||| it (DIAG-LOC-1).
    ReportAtCaller

||| A library's cells, one per purpose.
record Row where
  constructor MkRow
  trusted, admitted, breakLast, reportAtCaller : Bool

||| The table, one row per library. `Admitted` is off for `PrimIO`, which
||| admits only what `admittedFromPrimIO` lists.
|||
|||                         trusted admitted break-last report
row : Lib -> Row
row Builtin  = MkRow        True    True     True       True
row PrimIO   = MkRow        True    False    True       True
row Prelude  = MkRow        True    True     False      True
row (Base _) = MkRow        True    True     False      False

column : Purpose -> Row -> Bool
column Trusted = (.trusted)
column Admitted = (.admitted)
column BreakLast = (.breakLast)
column ReportAtCaller = (.reportAtCaller)

||| Does a purpose cover code of this origin? The user's code and generated
||| code are in no library.
export
covers : Purpose -> Origin -> Bool
covers p (Library l) = column p (row l)
covers _ _ = False

||| The origin of the code in a module, by the module's path, outermost
||| first. `Builtin` and `PrimIO` are exactly those modules; the Prelude and
||| base's areas are their namespaces.
export
moduleOrigin : List String -> Origin
moduleOrigin ["Builtin"] = Library Builtin
moduleOrigin ["PrimIO"] = Library PrimIO
moduleOrigin ("Prelude" :: _) = Library Prelude
moduleOrigin ("Data" :: _) = Library (Base Data)
moduleOrigin ("Control" :: _) = Library (Base Control)
moduleOrigin ("Decidable" :: _) = Library (Base Decidable)
moduleOrigin ("Syntax" :: _) = Library (Base Syntax)
moduleOrigin _ = User

------------------------------------------------------------------------------
-- Policy by definition
------------------------------------------------------------------------------

||| PROF-LIB-1: what `PrimIO` admits. Its other definitions (pointers,
||| threads and their foreign calls) are not admitted.
admittedFromPrimIO : List String
admittedFromPrimIO =
  [ "IORes", "MkIORes", "PrimIO", "IO", "MkIO", "prim__io_pure", "io_pure"
  , "prim__io_bind", "io_bind", "fromPrim", "toPrim", "unsafePerformIO"
  , "unsafeCreateWorld", "unsafeDestroyWorld" ]

||| PROF-LIB-1: is a definition of this origin admitted? The name is the
||| definition's own, or for a case or with block its parent's. `Builtin`'s
||| escape hatches are admitted like the rest of it: Idris flags them
||| (`isEscapeHatch`), and PROF-ESC-1 rejects them on that flag first.
export
admits : Origin -> QName -> Bool
admits o q = covers Admitted o || (q.space == ["PrimIO"] && elem q.name admittedFromPrimIO)

||| PROF-ESC-1: a totality assertion, an escape hatch that changes no value.
||| A trusted library's own are trusted; the user's are rejected on Idris's
||| flag like any other escape hatch.
export
assertion : QName -> Bool
assertion q = q == MkQName ["Builtin"] "assert_total"
