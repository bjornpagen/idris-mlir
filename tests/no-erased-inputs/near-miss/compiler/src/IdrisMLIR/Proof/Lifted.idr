-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module IdrisMLIR.Proof.Lifted

||| no CExp, no NamedCExp and no ANF: the documentation is no code
-- getCompileData would erase the facts the passes need
public export
data Lifted : Type where
  MkLifted : Lifted

note : String
note = "CExp and treeRT in a string"

cexpLike : Nat
cexpLike = 0

NamedCExpr : Type
NamedCExpr = Nat
