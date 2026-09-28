||| The rules of docs/architecture/ that the compiler reports, as data. A
||| diagnostic names its rule (DIAG-CODE-1), so a misspelt rule is a type
||| error, not a wrong message. The frontend checks most of them; the
||| profile rules on the optimized module (`PROF-TYPE-4`, `PROF-DATA-3`,
||| `PROF-PRIM-4`, `PROF-HEAP-1` to `-4`) also come back from
||| `idris-mlir-cc`, which names them in its text (`parseRule`).
module IdrisMLIR.Rule


import Data.List

%default total

public export
data Rule
  = ProfProg1 | ProfProg2 | ProfProg4
  | ProfLib1 | ProfIO3 | ProfIO4
  | ProfType4
  | ProfData2 | ProfData3 | ProfData5
  | ProfFn1 | ProfFn5 | ProfFn7
  | ProfPoly1 | ProfTerm2
  | ProfPrim2 | ProfPrim4
  | ProfHeap1 | ProfHeap2 | ProfHeap3 | ProfHeap4
  | ProfEsc1 | ProfPrag1
  | FeEntry4 | FeTtc1 | FeTr7
  | HookShape1

export
Show Rule where
  show ProfProg1 = "PROF-PROG-1"
  show ProfProg2 = "PROF-PROG-2"
  show ProfProg4 = "PROF-PROG-4"
  show ProfLib1 = "PROF-LIB-1"
  show ProfIO3 = "PROF-IO-3"
  show ProfIO4 = "PROF-IO-4"
  show ProfType4 = "PROF-TYPE-4"
  show ProfData2 = "PROF-DATA-2"
  show ProfData3 = "PROF-DATA-3"
  show ProfData5 = "PROF-DATA-5"
  show ProfFn1 = "PROF-FN-1"
  show ProfFn5 = "PROF-FN-5"
  show ProfFn7 = "PROF-FN-7"
  show ProfPoly1 = "PROF-POLY-1"
  show ProfTerm2 = "PROF-TERM-2"
  show ProfPrim2 = "PROF-PRIM-2"
  show ProfPrim4 = "PROF-PRIM-4"
  show ProfHeap1 = "PROF-HEAP-1"
  show ProfHeap2 = "PROF-HEAP-2"
  show ProfHeap3 = "PROF-HEAP-3"
  show ProfHeap4 = "PROF-HEAP-4"
  show ProfEsc1 = "PROF-ESC-1"
  show ProfPrag1 = "PROF-PRAG-1"
  show FeEntry4 = "FE-ENTRY-4"
  show FeTtc1 = "FE-TTC-1"
  show FeTr7 = "FE-TR-7"
  show HookShape1 = "HOOK-SHAPE-1"

||| Every rule, to read one back from its name.
allRules : List Rule
allRules =
  [ ProfProg1, ProfProg2, ProfProg4, ProfLib1, ProfIO3, ProfIO4, ProfType4
  , ProfData2, ProfData3, ProfData5, ProfFn1, ProfFn5, ProfFn7, ProfPoly1, ProfTerm2
  , ProfPrim2, ProfPrim4, ProfHeap1, ProfHeap2, ProfHeap3, ProfHeap4, ProfEsc1, ProfPrag1
  , FeEntry4, FeTtc1, FeTr7, HookShape1 ]

||| A rule by its name, as `idris-mlir-cc` reports it.
export
parseRule : String -> Maybe Rule
parseRule name = find (\r => show r == name) allRules
