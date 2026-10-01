||| The library table: where code comes from, and what each purpose of the
||| compiler makes of each library. The purposes differ: only `Trusted` and
||| `Admitted` cover base, `BreakLast` leaves out the Prelude, and `Admitted`
||| covers `PrimIO` only for what it lists.
module IdrisMLIR.Registry.Libraries

import IdrisMLIR.Registry.Name

%default total

||| The areas of a trusted package that the profile trusts, by their top
||| namespace.
public export
data Area = Data | Control | Decidable | Syntax

||| The libraries the compiler knows: `Builtin` and `PrimIO`, the Prelude's
||| modules, and the trusted areas of the packages base and linear.
public export
data Lib = Builtin | PrimIO | Prelude | Base Area | Linear Area

||| Where Idris found the TTC of a module: in the project's own build
||| directory, built from the user's source; in the pinned installation's
||| package of that name; or anywhere else. A module's name says nothing
||| about which of these it is, so trust never follows from a name.
public export
data Home = Project | Installed String | Elsewhere

||| Where code comes from. The registry computes it once, when TT is
||| translated, and every location carries it (`Loc`), so no pass reads a
||| namespace. `Untrusted` is library code outside the table: a program
||| may load it, but not reach it. Code in no module (a primitive, a
||| location Idris does not have) is `Generated`.
public export
data Origin = User | Library Lib | Untrusted | Generated

||| What the compiler asks of a library.
public export
data Purpose
  = ||| An IO program may import it, its source is not lexed for pragmas,
    ||| and its definitions must be admitted.
    Trusted
  | ||| Every definition of it is admitted.
    Admitted
  | ||| A function of it is chosen as a loop breaker only when its cycle has
    ||| no function from elsewhere.
    BreakLast
  | ||| A diagnostic inside it is reported at the user's code that reached
    ||| it.
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
row (Linear _) = MkRow      True    True     False      False

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

||| A trusted area, by its top namespace.
area : String -> Maybe Area
area "Data" = Just Data
area "Control" = Just Control
area "Decidable" = Just Decidable
area "Syntax" = Just Syntax
area _ = Nothing

||| The origin of the code in a module, by where its TTC is and the
||| module's path, outermost first. The Prelude package holds `Builtin`,
||| `PrimIO` and the Prelude; a trusted area of base or linear is its top
||| namespace within that package.
export
moduleOrigin : Home -> List String -> Origin
moduleOrigin Project _ = User
moduleOrigin (Installed "prelude") ["Builtin"] = Library Builtin
moduleOrigin (Installed "prelude") ["PrimIO"] = Library PrimIO
moduleOrigin (Installed "prelude") ("Prelude" :: _) = Library Prelude
moduleOrigin (Installed "base") (top :: _) = maybe Untrusted (Library . Base) (area top)
moduleOrigin (Installed "linear") (top :: _) = maybe Untrusted (Library . Linear) (area top)
moduleOrigin _ _ = Untrusted

------------------------------------------------------------------------------
-- Policy by definition
------------------------------------------------------------------------------

||| What `PrimIO` admits. Its other definitions (pointers,
||| threads and their foreign calls) are not admitted.
admittedFromPrimIO : List String
admittedFromPrimIO =
  [ "IORes", "MkIORes", "PrimIO", "IO", "MkIO", "prim__io_pure", "io_pure"
  , "prim__io_bind", "io_bind", "fromPrim", "toPrim", "unsafePerformIO"
  , "unsafeCreateWorld", "unsafeDestroyWorld" ]

||| Is a definition of this origin admitted? The name is the
||| definition's own, or for a case or with block its parent's. `Builtin`'s
||| escape hatches are admitted like the rest of it: Idris flags them
||| (`isEscapeHatch`), and the escape-hatch check rejects them on that flag
||| first.
export
admits : Origin -> QName -> Bool
admits o q = covers Admitted o || (q.space == ["PrimIO"] && elem q.name admittedFromPrimIO)

||| A totality assertion, an escape hatch that changes no value.
||| A trusted library's own are trusted; the user's are rejected on Idris's
||| flag like any other escape hatch.
export
assertion : QName -> Bool
assertion q = q.space == ["Builtin"] && elem q.name ["assert_total", "assert_smaller"]
