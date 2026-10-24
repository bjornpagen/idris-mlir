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
||| lifetime parameter at 0, each position in 32 bits.
export
livesInWire : Composite
livesInWire = MkComposite "LivesIn" "::idr::LivesIn"
  (Fields [ MkWireField "value" (WireLeaf LeafWord32)
          , MkWireField "lifetime" (WireLeaf LeafWord32) ])
  (brief "a scoped parameter or result and the lifetime parameter it lives in")

||| One bound: `0 >= 1`, the lifetime parameter at 0 lives at least as long
||| as the one at 1, each position in 32 bits.
export
outlivesWire : Composite
outlivesWire = MkComposite "Outlives" "::idr::Outlives"
  (Fields [ MkWireField "longer" (WireLeaf LeafWord32)
          , MkWireField "shorter" (WireLeaf LeafWord32) ])
  (brief "a lifetime parameter that lives at least as long as another")

||| The entries' text, `(2 in 0, 3 in 0)`; their bytecode is the wire's.
export
livesInEntriesDirective : Directive
livesInEntriesDirective = MkDirective
  { name = "LivesInEntries"
  , args = []
  , doc = brief "scoped values and the lifetime parameters they live in: `(2 in 0, 3 in 0)`"
  }

||| The bounds' text, `(0 >= 1)`; their bytecode is the wire's.
export
outlivesDirective : Directive
outlivesDirective = MkDirective
  { name = "OutlivesBounds"
  , args = []
  , doc = brief "lifetime parameters that outlive others: `(0 >= 1)`"
  }

||| The scoped parameters, or the scoped results, each with the lifetime
||| parameter it lives in.
livesInEntries : ParamKind
livesInEntries = WiredValue (WiredArray (WireOf livesInWire)) livesInEntriesDirective

||| `#idr.lives_in<(2 in 0) -> (0 in 0) where (0 >= 1)>`, C++ `LivesInAttr`:
||| the scoped parameters, then the scoped results, each with the lifetime
||| parameter it lives in, and the bounds between lifetime parameters.
export
livesInAttr : AttrDef 3
livesInAttr = MkAttrDef
  { mnemonic = "lives_in"
  , params =
      [ MkParameter "parameters" livesInEntries AlwaysWritten
          "each scoped parameter, in order, and the lifetime parameter it lives in"
      , MkParameter "results" livesInEntries AlwaysWritten
          "each scoped result, in order, and the lifetime parameter it lives in"
      , MkParameter "bounds" (WiredValue (WiredArray (WireOf outlivesWire)) outlivesDirective)
          AlwaysWritten "the lifetime parameters that outlive others" ]
  , syntax = HandSyntax
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
      , MkMember OnObjectConst "::mlir::FailureOr<::idr::LivesInAttr>" "renumber"
          [ param "::llvm::ArrayRef<::std::optional<uint32_t>>" "parameters"
          , param "::llvm::ArrayRef<::std::optional<uint32_t>>" "results" ] ]
  , doc = MkDoc "where a function's scoped parameters and results live"
      """
      On idr.func exactly when a parameter or a result is scoped or a bound
      is declared, every scoped one listed once; on idr.call, its callee's.
      Restating a value's lifetime, or moving the signature's positions,
      keeps it so; a move that would leave a value without its lifetime has
      no statement.
      """
  }
