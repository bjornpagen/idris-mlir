||| The idr dialect's syntax that is C++, not ODS, so not generated with the
||| rest of the dialect (IdrisMLIR.Dialect.Idr): a closure's type, whose
||| type lists FnType::print writes in parentheses, and the dialect's
||| spellings of a value at a grade, which IdrDialect::printType writes for
||| a QType, whose grade is a C++ struct.
module IdrisMLIR.CustomSyntax

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.MLIR

%default total

||| A closure taking `ins` and giving `outs`: `!idr.fn<(A...) -> (R...)>`.
export
fnType : List MlirType -> List MlirType -> MlirType
fnType ins outs =
  MkMlirType ("!idr.fn<(" ++ commaSeparated (map (.text) ins) ++ ") -> (" ++
              commaSeparated (map (.text) outs) ++ ")>")

||| A value of quantity 1, other than the world: `!idr.lin<T>`.
export
lin : MlirType -> MlirType
lin t = MkMlirType ("!idr.lin<" ++ t.text ++ ">")

||| The erased value, of quantity 0 and of no carrier.
export
erased : MlirType
erased = MkMlirType "!idr.erased"

||| The world, at its one grade (1, ·): the dialect reads its carrier's
||| spelling as that.
export
world : MlirType
world = worldType
