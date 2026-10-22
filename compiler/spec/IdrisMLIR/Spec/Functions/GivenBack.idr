-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a function gives back: on every path that returns, which component
||| of which argument a component of a result is, the same value and not an
||| equal one. Only the optimizer's proof writes it, and no call holds a
||| copy. The lowering gives back the register it was passed, and a tail
||| call's callee gives back exactly the result components its caller does,
||| since a tail call and its caller lower to one return: a result dropped
||| from one is dropped from every one.
|||
||| A component is a value's place in the inline layout its type fixes: the
||| value at a position, then down through fields of constructors laid out
||| inline. Each entry is its own small attribute holding its two paths, so
||| the attribute's storage owns every field position it names.
module IdrisMLIR.Spec.Functions.GivenBack

import IdrisMLIR.Spec.Core.Vocabulary

import Data.Fin
import Data.Vect

%default total

||| A result's or an argument's position, `1`, in 32 bits, or an axis of
||| its shape; its text is printed in its path or its extent.
export
positionDirective : Directive
positionDirective = MkDirective
  { name = "Position"
  , args = []
  , doc = brief "a position in a signature, or an axis of a shape: `1`"
  }

||| The fields down to a component, `[0, 2]`, or nothing for the whole
||| value, each a field's position within its constructor in 32 bits.
export
fieldPathDirective : Directive
fieldPathDirective = MkDirective
  { name = "FieldPath"
  , args = []
  , doc = brief "the fields down to a component: `[0, 2]`, or nothing for the whole value"
  }

||| The entries of `#idr.given_back`, `[0 <- 2, 1[0] <- 0[1]]`, each the
||| attribute it is.
export
givenBackEntriesDirective : Directive
givenBackEntriesDirective = MkDirective
  { name = "GivenBackEntries"
  , args = []
  , doc = brief "result components and the argument components they are: `[0 <- 2, 1[0] <- 0[1]]`"
  }

||| A position in a signature, or an axis: one codec for every 32-bit
||| place a function's attributes name.
export
positionKind : ParamKind
positionKind = WiredValue (WiredOne LeafWord32) positionDirective

||| The fields down to a component.
fieldPathKind : ParamKind
fieldPathKind = WiredValue (WiredArray (WireLeaf LeafWord32)) fieldPathDirective

||| `#idr.given_back.entry<1[0] <- 0[1]>`, C++ `GivenBackEntryAttr`: result
||| component `1[0]` is argument component `0[1]`. Printed inside
||| `#idr.given_back` without its own name.
export
givenBackEntryAttr : AttrDef 4
givenBackEntryAttr = MkAttrDef
  { mnemonic = "given_back.entry"
  , params =
      [ MkParameter "result" positionKind AlwaysWritten "the result the component is of"
      , MkParameter "result_fields" fieldPathKind AlwaysWritten
          "the fields down to the component, through constructors laid out inline"
      , MkParameter "argument" positionKind AlwaysWritten "the argument the component is of"
      , MkParameter "argument_fields" fieldPathKind AlwaysWritten
          "the fields down to the argument's component" ]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , members = [MkMember OnObjectConst "::idr::GivenBackEntry" "entry" []]
  , doc = brief "a result component and the argument component it is"
  }

||| `#idr.given_back<[0 <- 2, 1[0] <- 0[1]]>`, C++ `GivenBackAttr`: the
||| entries, in increasing order of result path, none twice. Built by the
||| optimizer from entries whose field positions live anywhere: the
||| attribute copies them.
export
givenBackAttr : AttrDef 1
givenBackAttr = MkAttrDef
  { mnemonic = "given_back"
  , params =
      [ MkParameter "entries"
          (WiredValue (WiredArray (WireLeaf (LeafAttr "::idr::GivenBackEntryAttr")))
                      givenBackEntriesDirective)
          AlwaysWritten "each result component given back, in order of its path" ]
  , syntax = Declarative [Keyword "<", ParamAt FZ, Keyword ">"]
  , typed = Untyped
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members =
      [ MkMember OnClass "::idr::GivenBackAttr" "get"
          [ param "::mlir::MLIRContext *" "context"
          , param "::llvm::ArrayRef<::idr::GivenBackEntry>" "entries" ]
      , MkMember OnObjectConst "::idr::GivenBackAttr" "renumber"
          [ param "::llvm::ArrayRef<::std::optional<uint32_t>>" "parameters"
          , param "::llvm::ArrayRef<::std::optional<uint32_t>>" "results" ] ]
  , doc = MkDoc "what a function gives back of its arguments"
      """
      On every path that returns, each listed component of the result is the
      listed component of the arguments: the same value. Absent from a
      function that gives back nothing. Moving the signature's positions
      keeps it so.
      """
  }
