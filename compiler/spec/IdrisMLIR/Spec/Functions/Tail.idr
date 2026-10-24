-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Where a call stands in its function, the one fact held as the call's
||| op: a call in tail position never grows the stack, so whether it is one
||| is decided once, by the one definition of tail position, and lowered as
||| a jump. The frontend writes every call ordinary, which promises
||| nothing: no source syntax states a tail call or a context. Where the
||| program becomes first order, the one definition decides where every
||| call stands and makes it the op its standing makes, a tail call or a
||| self call modulo a context, a context still read before counting. From
||| then on every call's op is that definition's answer, made again by each
||| pass that makes or moves a call or changes what follows one, and
||| verified after every pass. The three ops are one family, its members
||| from the list of standings; what each obliges and how it is decided and
||| checked belong to the tail calls' own code, which each member's verifier
||| and its function's call.
module IdrisMLIR.Spec.Functions.Tail

import IdrisMLIR.Spec.Core.Vocabulary

import Data.List.Elem
import Data.List1

%default total

||| A call returns to its caller, which goes on (`Returns`); its result is
||| the caller's own result, given on through ops that do nothing at run
||| time, so it is a jump (`Tail`); or its result fills the one pending
||| field of cells its caller builds for it, so it is a loop with a
||| destination (`ModuloContext`).
public export
data CallStanding = Returns | Tail | ModuloContext

public export
callStandingClosed : Closed CallStanding
callStandingClosed = MkClosed
  { name = "CallStanding"
  , shape = OneOf
  , every = Returns ::: [Tail, ModuloContext]
  , complete = \case
      Returns => Here
      Tail => There Here
      ModuloContext => There (There Here)
  , describe = \case
      Returns => MkCase "Returns" (word "returns" ::: []) "returns to its caller, which goes on"
      Tail => MkCase "Tail" (word "tail" ::: []) "its result is its caller's, so the call is a jump"
      ModuloContext => MkCase "ModuloContext" (word "modulo_context" ::: [])
                         "its result fills a field of cells built before it, so the call is a loop"
  , doc = MkDoc "where a call stands in its function"
      """
      The constant of each member of the call family, so a call's standing
      is its op and no attribute holds it. The frontend makes every call
      ordinary; where the program becomes first order, the one definition of
      tail position makes each call the member its standing names, and from
      then on every call's member is its answer, made again by each pass
      that makes or moves a call or changes what follows one.
      """
  }

||| The mnemonic of each member of the call family.
public export
callMember : CallStanding -> Mnemonic
callMember Returns = "call"
callMember Tail = "tail_call"
callMember ModuloContext = "context_call"

||| The C++ case of each member's constant.
public export
callStandingCase : CallStanding -> Ident
callStandingCase Returns = "Returns"
callStandingCase Tail = "Tail"
callStandingCase ModuloContext = "ModuloContext"
