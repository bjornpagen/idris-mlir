-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A guard a partial op takes, an op of ours or an admitted upstream one:
||| the frontend builds it before the op from what the specification states,
||| so no writer places it by hand and no op is written without it.
module IdrisMLIR.Spec.Core.Guard

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Enums

import Data.List1

%default total

||| The guard op, the operand groups it is given (the one it guards first),
||| and the cause its crash names. A group is named by its position among
||| the op's operand groups, of the type `position`: a `Fin` for an op of
||| ours, whose groups the specification holds; a number for an admitted
||| op, whose groups are upstream's record's, so the backend that reads
||| that record is where a position past its groups is refused.
public export
record Guard (position : Type) where
  constructor MkGuard
  check : Mnemonic
  given : List1 position
  cause : CaseRef
