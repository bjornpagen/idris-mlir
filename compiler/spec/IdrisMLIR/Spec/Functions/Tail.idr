-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Where a call stands in its function, one fact held on the call: a call
||| in tail position never grows the stack, so whether it is one is decided
||| once, by the one definition of tail position, written on the call by
||| the frontend and by each pass that makes or moves a call, verified
||| after every pass, and lowered as a jump. The slot is the call's; what
||| each case obliges and how it is decided and checked belong to the tail
||| calls' own code, which the call's verifier and its function's call.
module IdrisMLIR.Spec.Functions.Tail

import IdrisMLIR.Spec.Core.Vocabulary

import Data.List.Elem
import Data.List1

%default total

||| A call returns to its caller, which goes on (`nontail`); its result is
||| the caller's own result, so it is a jump (`tail`); or its result fills
||| the one pending field of cells the caller built for it before the call,
||| so it is a loop with a destination (`modulo_context`).
public export
data TailKind = NonTail | Tail | ModuloContext

public export
tailKindClosed : Closed TailKind
tailKindClosed = MkClosed
  { name = "TailKind"
  , shape = OneOf
  , every = NonTail ::: [Tail, ModuloContext]
  , complete = \case
      NonTail => Here
      Tail => There Here
      ModuloContext => There (There Here)
  , describe = \case
      NonTail => MkCase "nontail" ("nontail" ::: []) "returns to its caller, which goes on"
      Tail => MkCase "tail" ("tail" ::: []) "its result is its caller's, so the call is a jump"
      ModuloContext => MkCase "modulo_context" ("modulo_context" ::: [])
                         "its result fills a field of cells built before it, so the call is a loop"
  , doc = MkDoc "where a call stands in its function"
      """
      Written on every call with no default: the frontend and each pass that
      makes or moves a call decide it by the one definition of tail position.
      """
  }
