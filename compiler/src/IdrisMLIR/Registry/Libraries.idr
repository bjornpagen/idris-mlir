||| The library table: where code comes from, and what each purpose of the
||| compiler makes of each library. The purposes differ: only `Trusted` and
||| `Admitted` cover base, `BreakLast` leaves out the Prelude, and `Admitted`
||| covers `PrimIO` only for what it lists.
module IdrisMLIR.Registry.Libraries

import IdrisMLIR.Registry.Name

%default total

||| The libraries the compiler knows: `Builtin` and `PrimIO`, the rest of
||| the prelude, base, and the packages this compiler ships itself
||| (`libs/`: `mlir-linear`), which it implements in full. The compiler
||| implements Idris 2 for programs over the upstream prelude and base; the
||| other packages shipped with Idris (contrib, linear, network, test) are
||| no commitment, and what they covered comes from `libs/`. A module of
||| prelude or base is one of these because its TTC lives in that package,
||| not because its name was listed.
public export
data Lib = Builtin | PrimIO | Prelude | Base | InHouse

||| Where Idris found the TTC of a module: in the project's own build
||| directory, built from the user's source; in an installed package of
||| that name; or anywhere else. A module's name says nothing about which
||| of these it is, so trust never follows from a name.
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
row Builtin = MkRow        True    True     True       True
row PrimIO  = MkRow        True    False    True       True
row Prelude = MkRow        True    True     False      True
row Base    = MkRow        True    True     False      False
row InHouse = MkRow        True    True     False      False

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

||| The origin of the code in a module, by the package its TTC lives in.
||| Every module of the prelude package is trusted: `Builtin` and `PrimIO`
||| keep the rows that admit them differently, and the rest of that package
||| is the Prelude. Every module of base is base. Every module of a package
||| this compiler ships is its own. A module of any other installed package
||| is untrusted, whatever it is named.
export
moduleOrigin : Home -> List String -> Origin
moduleOrigin Project _ = User
moduleOrigin (Installed "prelude") ("Builtin" :: _) = Library Builtin
moduleOrigin (Installed "prelude") ("PrimIO" :: _) = Library PrimIO
moduleOrigin (Installed "prelude") _ = Library Prelude
moduleOrigin (Installed "base") _ = Library Base
moduleOrigin (Installed "mlir-linear") _ = Library InHouse
moduleOrigin _ _ = Untrusted

||| The packages every program sees, whether it asks for them or not, as
||| Idris adds them: their directories are found under the prefix or on the
||| package search path.
export
defaultPackages : List String
defaultPackages = ["prelude", "base"]

------------------------------------------------------------------------------
-- Policy by definition
------------------------------------------------------------------------------

||| What `PrimIO` admits: the IO types and their operations, and the
||| pointers, which are the runtime's handles, with their operations.
||| Threads and collector finalizers are outside the language, refused by
||| name; anything else of `PrimIO` is not admitted.
admittedFromPrimIO : List String
admittedFromPrimIO =
  [ "IORes", "MkIORes", "PrimIO", "IO", "MkIO", "prim__io_pure", "io_pure"
  , "prim__io_bind", "io_bind", "fromPrim", "toPrim", "unsafePerformIO"
  , "unsafeCreateWorld", "unsafeDestroyWorld", "AnyPtr", "Ptr", "prim__nullAnyPtr"
  , "prim__getNullAnyPtr", "prim__castPtr", "prim__forgetPtr", "prim__nullPtr" ]

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
