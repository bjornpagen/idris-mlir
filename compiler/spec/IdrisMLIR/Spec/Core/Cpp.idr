-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A header of constants an area of the dialect gives its C++: its closed
||| sets as enums, their facts as tables indexed by them, relations as
||| arrays, each a compile-time constant read by a load, never a switch; and
||| its closed sums as variants of plain structs. The area states the
||| values; the generator prints them, under
||| `foreign/idr/include/idr/IR/Generated/<name>.h.inc`, where the area's
||| hand header includes them. No branch, no function body and no concept
||| can be stated here, so none is printed.
module IdrisMLIR.Spec.Core.Cpp

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Types

import Data.List1

%default total

||| One declaration of a header.
public export
data CppDecl : Type where
  ||| An enum or set of the dialect's, its cases in order.
  EnumOf : EnumDef -> CppDecl
  ||| A closed set and its columns: the enum and one array per column.
  TableOf : Table -> CppDecl
  ||| An array of one value per row.
  Array1 : Ident -> ColumnType -> List Cell -> Line -> CppDecl
  ||| An array of arrays: a relation or an operation's table over two
  ||| closed sets, `name[a][b]`.
  Array2 : Ident -> ColumnType -> List (List Cell) -> Line -> CppDecl
  ||| One constant.
  Scalar : Ident -> ColumnType -> Cell -> Line -> CppDecl
  ||| A closed sum: its set (the enum, printed with it), the `std::variant`
  ||| it is, by name, of one struct per case in the set's order, named by
  ||| its case and holding that case's members (one list per case, in the
  ||| set's order, which `sumOf` makes), compared member by member.
  SumOf : EnumDef -> Ident -> List (List WireField) -> Line -> CppDecl

||| A closed sum over a closed set: each case's members, a total function,
||| so a case the set gains without its members does not build.
public export
sumOf : (c : Closed a) -> (name : Ident) -> (a -> List WireField) -> Line -> CppDecl
sumOf c name members doc = SumOf (enumDef c) name (map members (forget c.every)) doc

||| Where a block of a header declares its names: the dialect's own
||| namespace, `::idr`, where ODS declares the dialect's enums, so a table
||| there names an enum ODS or the block declares; or a namespace nested in
||| it, `::idr::<path>`, whose block declares every enum its tables name.
public export
data Namespace = DialectNamespace | Nested (List1 Ident)

||| A header: its file name, and its declarations by namespace, in order.
public export
record Header where
  constructor MkHeader
  name : Ident
  blocks : List (Namespace, List CppDecl)
  doc : Doc
