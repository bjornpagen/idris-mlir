-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The library table: where code comes from, and what each purpose of the
||| compiler makes of each library. The purposes differ: `Admitted` covers
||| `PrimIO` only for the definitions the registry's entries admit
||| (`Admission`), and `ReportAtCaller` leaves out base and the packages
||| this compiler ships.
module IdrisMLIR.Registry.Libraries

%default total

||| The libraries the compiler knows: `Builtin` and `PrimIO`, the rest of
||| the prelude, base, the packages this compiler ships itself (`libs/`:
||| `mlir-linear` and `mlir-array`), which it implements in full, and
||| `Compiler`, the compiler's own Idris that the frontend is written over
||| (its type checker, `compiler/checker`, the package `idris-mlir-checker`,
||| and the dialect's specification, `compiler/spec`, the package
||| `idris-mlir-spec`), so that the frontend, and every program of ours
||| over them, compiles as a program. The compiler implements Idris 2 for
||| programs over the upstream prelude and base; the other packages
||| shipped with Idris (contrib, linear, network, test) are no commitment,
||| and what they covered comes from `libs/`. A module of prelude or base
||| is one of these because its TTC lives in that package, not because its
||| name was listed.
public export
data Lib = Builtin | PrimIO | Prelude | Base | InHouse | Compiler

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
  | ||| A diagnostic inside it is reported at the user's code that reached
    ||| it.
    ReportAtCaller

||| A library's cells, one per purpose.
record Row where
  constructor MkRow
  trusted, admitted, reportAtCaller : Bool

||| The table, one row per library. `Admitted` is off for `PrimIO`, which
||| admits only the definitions the registry's entries admit (`Admission`).
|||
|||                          trusted admitted report
row : Lib -> Row
row Builtin  = MkRow        True    True     True
row PrimIO   = MkRow        True    False    True
row Prelude  = MkRow        True    True     True
row Base     = MkRow        True    True     False
row InHouse  = MkRow        True    True     False
row Compiler = MkRow        True    True     False

column : Purpose -> Row -> Bool
column Trusted = (.trusted)
column Admitted = (.admitted)
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
||| this compiler ships is its own, and every module of its type checker
||| or of its specification is the compiler's: the frontend's own modules
||| (`IdrisMLIR.*` of `compiler/src`) are the project's, user code like any
||| program's. A module of any other installed package is untrusted,
||| whatever it is named.
export
moduleOrigin : Home -> List String -> Origin
moduleOrigin Project _ = User
moduleOrigin (Installed "prelude") ("Builtin" :: _) = Library Builtin
moduleOrigin (Installed "prelude") ("PrimIO" :: _) = Library PrimIO
moduleOrigin (Installed "prelude") _ = Library Prelude
moduleOrigin (Installed "base") _ = Library Base
moduleOrigin (Installed "mlir-linear") _ = Library InHouse
moduleOrigin (Installed "mlir-array") _ = Library InHouse
moduleOrigin (Installed "mlir-relational") _ = Library InHouse
moduleOrigin (Installed "mlir-hash") _ = Library InHouse
moduleOrigin (Installed "idris-mlir-checker") _ = Library Compiler
moduleOrigin (Installed "idris-mlir-spec") _ = Library Compiler
moduleOrigin _ _ = Untrusted

||| The packages every program sees, whether it asks for them or not, as
||| Idris adds them: their directories are found under the prefix or on the
||| package search path.
export
defaultPackages : List String
defaultPackages = ["prelude", "base"]
