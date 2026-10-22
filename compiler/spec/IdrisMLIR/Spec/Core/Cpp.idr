-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A header of constants an area of the dialect gives its C++: its closed
||| sets as enums, their facts as tables indexed by them, and relations as
||| arrays, each a compile-time constant read by a load, never a switch. The
||| area states the values; the generator prints them, under
||| `foreign/idr/include/idr/IR/Generated/<name>.h.inc`, where the area's
||| hand header includes them. No branch, no function body and no concept
||| can be stated here, so none is printed.
module IdrisMLIR.Spec.Core.Cpp

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Enums

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
