-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A closed set the dialect states and the C++ reads: its cases in
||| declaration order, each case's number its position, so no value is
||| ever skipped or given twice, and each case's spelling in the IR. Two
||| shapes: an enum, a value that is one case; and a set of cases, a value
||| that holds any of them, as a row of effect atoms does. The specification
||| keeps the Idris `data` beside it, which the frontend imports (a closed
||| set is imported, never printed back into Idris); `cases` lists the
||| constructors once, and `complete` proves no constructor is missing.
module IdrisMLIR.Spec.Core.Enums

import IdrisMLIR.Spec.Core.Text

import Data.Fin
import Data.List
import Data.List.Elem
import Data.List1

%default total

||| An enum, one case at a time, or a set of cases.
public export
data EnumShape = OneOf | SetOf

||| A case: its C++ name, its spelling in the IR (an enum parameter is read
||| as a keyword, so a spelling is snake words, or several words that print
||| as a string), and what it means.
public export
record Case where
  constructor MkCase
  name : Ident
  spelling : List1 Word
  doc : Line

||| The spelling as the IR prints it: its words joined by spaces.
public export
spellingText : Case -> String
spellingText c = concat (intersperse " " (map wordText (forget c.spelling)))

||| An enum or set of the dialect, as ODS and the C++ hold it: its C++
||| name in `::idr`, its cases in order.
public export
record EnumDef where
  constructor MkEnumDef
  name : Ident
  shape : EnumShape
  cases : List1 Case
  doc : Doc

||| A closed set stated once in Idris: its constructors listed in order,
||| with the proof that the list holds every one, and what each case is.
||| `enumDef` makes the dialect's enum from it, so the Idris constructors
||| and the C++ cases cannot drift: the list is the one order. The proof is
||| kept: walking it is how a value finds its position, the number C++ and
||| bytecode hold, so it is the computation, not a check beside it.
public export
record Closed (a : Type) where
  constructor MkClosed
  name : Ident
  shape : EnumShape
  every : List1 a
  complete : (x : a) -> Elem x (forget every)
  describe : a -> Case
  doc : Doc

public export
enumDef : Closed a -> EnumDef
enumDef c = MkEnumDef c.name c.shape (map c.describe c.every) c.doc

||| A case of a closed set as the C++ names it, made from the case's value,
||| so it cannot name a case the set lacks: an op's crash cause, a family's
||| constant, a table's cell.
public export
record CaseRef where
  constructor MkCaseRef
  enum : EnumDef
  name : Ident

public export
caseRef : Closed b -> b -> CaseRef
caseRef c x = MkCaseRef (enumDef c) (c.describe x).name

||| The case at a position of a closed set: how a printed module writes a
||| value of the set, by the position the generator computed of it, which
||| the module's type check holds to be one of the set's.
public export
caseAt : (c : Closed a) -> Fin (length (forget c.every)) -> a
caseAt c k = index' (forget c.every) k

||| The position of a value among its set's cases: its number in C++ and in
||| bytecode. Total: `complete` says it is there.
public export
position : (c : Closed a) -> (x : a) -> Nat
position c x = elemIndex (c.complete x)
  where
    elemIndex : {0 xs : List a} -> Elem x xs -> Nat
    elemIndex Here = 0
    elemIndex (There later) = S (elemIndex later)

------------------------------------------------------------------------------
-- A closed set the frontend writes values of
------------------------------------------------------------------------------

||| Where the Idris side finds a closed set it writes values of: the module
||| that declares its type, the type, and the module and name of the closed
||| set, whose order gives a value its position. The generated encoder
||| takes the value typed and writes its position, so the wire form is
||| written once and the frontend never holds a value as a bare number. A
||| wrong name is the generated module's compile error.
public export
record Source where
  constructor MkSource
  typeHome : List1 Ident
  typeName : Ident
  setHome : List1 Ident
  setName : Ident

||| A closed set a value of the dialect holds and the frontend writes: the
||| C++ enum, and where the Idris side finds it.
public export
record ImportedEnum where
  constructor MkImportedEnum
  enum : EnumDef
  source : Source

public export
imported : Closed a -> Source -> ImportedEnum
imported c s = MkImportedEnum (enumDef c) s

------------------------------------------------------------------------------
-- Tables
------------------------------------------------------------------------------

||| A value one column of a table holds for a case, printed as a C++
||| constant: an integer, a string, a case of another set of the dialect's
||| (by the set and the case), or a set of cases of one.
public export
data Cell
  = IntCell Integer
  | TextCell String
  | TruthCell Bool
  | CaseCell CaseRef
  | SetCell EnumDef (List Ident)

||| A set of cases of a closed set, by their values.
public export
setCell : Closed b -> List b -> Cell
setCell c xs = SetCell (enumDef c) (map (\x => (c.describe x).name) xs)

||| A column's C++ element type.
public export
data ColumnType
  = Signed64
  | Unsigned8
  | Unsigned32
  | Unsigned64
  | TextColumn
  | TruthColumn
  | EnumColumn EnumDef
  | SetColumn EnumDef

||| A column of facts over a closed set: its name and type, and the value of
||| each case, a total function, so a new case without its facts does not
||| build.
public export
record Column (a : Type) where
  constructor MkColumn
  name : Ident
  type : ColumnType
  value : a -> Cell
  doc : Line

||| A closed set with its columns, printed as the C++ enum and one
||| `constexpr` array per column indexed by it: every fact the C++ reads of
||| the set, a load at the case's position, never a switch.
public export
record Table where
  constructor MkTable
  enum : EnumDef
  columns : List (Ident, ColumnType, List Cell, Line)

public export
table : (c : Closed a) -> List (Column a) -> Table
table c cols = MkTable (enumDef c) (map row cols)
  where
    row : Column a -> (Ident, ColumnType, List Cell, Line)
    row col = (col.name, col.type, map col.value (forget c.every), col.doc)
