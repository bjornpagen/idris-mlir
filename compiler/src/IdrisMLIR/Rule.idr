||| The rules of docs/architecture/ that the compiler enforces, as data. A
||| diagnostic names its rule (DIAG-CODE-1), so a misspelt rule is a type
||| error, not a wrong message.
module IdrisMLIR.Rule

import IdrisMLIR.Loc

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
  | ProfHeap1 | ProfHeap2 | ProfHeap3 | ProfHeap4 | ProfHeap5
  | ProfEsc1 | ProfPrag1
  | FeEntry4 | FeEntry5 | FeTtc1 | FeTr3 | FeTr4 | FeTr7
  | HookShape1
  | CoreCheck1
  | CoreInv1 | CoreInv2 | CoreInv3 | CoreInv5 | CoreInv6 | CoreInv7 | CoreInv8 | CoreInv9

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
  show ProfHeap5 = "PROF-HEAP-5"
  show ProfEsc1 = "PROF-ESC-1"
  show ProfPrag1 = "PROF-PRAG-1"
  show FeEntry4 = "FE-ENTRY-4"
  show FeEntry5 = "FE-ENTRY-5"
  show FeTtc1 = "FE-TTC-1"
  show FeTr3 = "FE-TR-3"
  show FeTr4 = "FE-TR-4"
  show FeTr7 = "FE-TR-7"
  show HookShape1 = "HOOK-SHAPE-1"
  show CoreCheck1 = "CORE-CHECK-1"
  show CoreInv1 = "CORE-INV-1"
  show CoreInv2 = "CORE-INV-2"
  show CoreInv3 = "CORE-INV-3"
  show CoreInv5 = "CORE-INV-5"
  show CoreInv6 = "CORE-INV-6"
  show CoreInv7 = "CORE-INV-7"
  show CoreInv8 = "CORE-INV-8"
  show CoreInv9 = "CORE-INV-9"

||| A diagnostic (DIAG-FMT-1): the violated rule, the definition it concerns,
||| where, and what.
public export
record Diag where
  constructor MkDiag
  rule : Rule
  owner : String
  loc : Loc
  message : String
