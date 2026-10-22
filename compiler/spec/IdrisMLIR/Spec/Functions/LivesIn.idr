-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Where a function's scoped parameters and results live: each one names
||| the lifetime parameter it lives in, and the signature states which
||| lifetime parameters outlive which. A function states its parameters'
||| lifetimes in its signature, as an op states the lifetime of a scoped
||| value it makes, so a value's lifetime is one hop from it inside the
||| body; and a call states its scoped results' lifetimes as its own
||| lifetime operands at the same positions, a copy of its callee's
||| signature held equal to it, so a pass on the caller reads them with no
||| lookup of the callee.
|||
||| Positions are the signature's own, a parameter's or a result's, so
||| rewriting a parameter's type does not move what another entry names;
||| each list is sorted by the position it states a lifetime for. Which
||| lifetime parameters something may be put into is their kind, in the
||| type; how much is the function's record beside its row.
module IdrisMLIR.Spec.Functions.LivesIn

import IdrisMLIR.Spec.Core.Vocabulary

import Data.Fin
import Data.Vect

%default total

||| One entry: `2 in 0`, the parameter or result at 2 lives in the
||| lifetime parameter at 0.
export
livesInDirective : Directive
livesInDirective = MkDirective
  { name = "LivesIn"
  , args = []
  , doc = brief "a scoped parameter or result and the lifetime parameter it lives in"
  }

||| One bound: `0 >= 1`, the lifetime parameter at 0 lives at least as long
||| as the one at 1.
export
outlivesDirective : Directive
outlivesDirective = MkDirective
  { name = "Outlives"
  , args = []
  , doc = brief "a lifetime parameter that lives at least as long as another"
  }

||| `#idr.lives_in<(2 in 0) -> (0 in 0) where (0 >= 1)>`, C++ `LivesInAttr`:
||| the scoped parameters, then the scoped results, each with the lifetime
||| parameter it lives in, and the bounds between lifetime parameters.
export
livesInAttr : AttrDef 3
livesInAttr = MkAttrDef
  { mnemonic = "lives_in"
  , params =
      [ MkParameter "parameters" (ListOf (HandValue "::idr::LivesIn" livesInDirective)) AlwaysWritten
          "each scoped parameter, in order, and the lifetime parameter it lives in"
      , MkParameter "results" (ListOf (HandValue "::idr::LivesIn" livesInDirective)) AlwaysWritten
          "each scoped result, in order, and the lifetime parameter it lives in"
      , MkParameter "bounds" (ListOf (HandValue "::idr::Outlives" outlivesDirective)) AlwaysWritten
          "the lifetime parameters that outlive others" ]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members =
      [ MkMember OnObjectConst "::std::optional<uint32_t>" "lifetimeOfParameter"
          [param "uint32_t" "parameter"]
      , MkMember OnObjectConst "::std::optional<uint32_t>" "lifetimeOfResult"
          [param "uint32_t" "result"]
      , MkMember OnClass "::idr::LivesInAttr" "restateParameter"
          [ param "::mlir::MLIRContext *" "context", param "::idr::LivesInAttr" "lives"
          , param "uint32_t" "parameter", param "::std::optional<uint32_t>" "lifetime" ]
      , MkMember OnClass "::idr::LivesInAttr" "restateResult"
          [ param "::mlir::MLIRContext *" "context", param "::idr::LivesInAttr" "lives"
          , param "uint32_t" "result", param "::std::optional<uint32_t>" "lifetime" ]
      , MkMember OnObjectConst "::idr::LivesInAttr" "renumberResults"
          [param "::llvm::ArrayRef<::std::optional<uint32_t>>" "to"] ]
  , doc = MkDoc "where a function's scoped parameters and results live"
      """
      On idr.func exactly when a parameter or a result is scoped or a bound
      is declared, every scoped one listed once; on idr.call, its callee's.
      Restating a value's lifetime, or erasing results, keeps it so.
      """
  }
