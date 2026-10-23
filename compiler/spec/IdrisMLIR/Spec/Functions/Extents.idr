-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Which index term each extent a function's signature leaves unknown is.
||| An array's type is upstream's ranked tensor, `?` at every axis whose
||| size is no constant, since MLIR's tensor type has no symbolic dimension;
||| where Idris's signature names that size by an index term, the function
||| holds the term, over its own binders, so a call that fixes the binders
||| fixes the size, and a specialized copy whose term becomes a size has
||| that axis static where it is a bare tensor input's. Where the type keeps
||| the axis `?` on purpose (a result, a graded array), the copy's entry
||| holds the constant, so a known size is never dropped. A result keeps
||| every axis `?`, a literal size too, its known size a constant entry, so
||| no cast follows a call. An entry says which term a `?` is and nothing
||| the type says: there is none for a static axis, and none for an axis no
||| term names. Bufferization makes
||| the tensor a buffer with the same axes, so an entry names an axis of
||| either.
|||
||| Each entry is its own small attribute holding its term, so the
||| attribute's storage owns the term's nodes; the function lists them in
||| the order of the axes they name, and moves them with their positions
||| when its signature is edited.
module IdrisMLIR.Spec.Functions.Extents

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Functions.GivenBack

import Data.Fin
import Data.List.Elem
import Data.List1
import Data.Vect

%default total

||| The side of a signature a value is on: among the function's arguments
||| or among its results. Inputs come first in the order entries are
||| listed in.
public export
data ExtentSide = OnInput | OnResult

public export
extentSideClosed : Closed ExtentSide
extentSideClosed = MkClosed
  { name = "ExtentSide"
  , shape = OneOf
  , every = OnInput ::: [OnResult]
  , complete = \case
      OnInput => Here
      OnResult => There Here
  , describe = \case
      OnInput => MkCase "Input" ("input" ::: []) "an argument of the function"
      OnResult => MkCase "Result" ("result" ::: []) "a result of the function"
  , doc = brief "the side of a function's signature a value is on"
  }

||| The entries of `#idr.extents`, `[input 0 axis 1 = v0, result 0 axis 0
||| = v0 + 1]`, each the attribute it is.
export
extentEntriesDirective : Directive
extentEntriesDirective = MkDirective
  { name = "ExtentEntries"
  , args = []
  , doc = brief "the axes a signature names by a term: `[input 0 axis 1 = v0, result 0 axis 0 = v0 + 1]`"
  }

||| `#idr.extent<input 0 axis 1 = v0>`, C++ `ExtentAttr`: axis 1 of the
||| function's argument 0 is `?` in its type, and its size is the term `v0`
||| over the function's binders. The term is one whole term in the
||| families' normal form, and never opaque, which names nothing. A
||| constant stands only where the type keeps the axis `?` on purpose,
||| which the function's verifier checks, since it reads the function's
||| types. Printed inside `#idr.extents` without its own name.
export
extentAttr : AttrDef 4
extentAttr = MkAttrDef
  { mnemonic = "extent"
  , params =
      [ MkParameter "side"
          (EnumValue (imported extentSideClosed
             (MkSource ("IdrisMLIR" ::: ["Spec", "Functions", "Extents"]) "ExtentSide"
                       ("IdrisMLIR" ::: ["Spec", "Functions", "Extents"]) "extentSideClosed")))
          AlwaysWritten "the side of the signature the value is on"
      , MkParameter "position" positionKind AlwaysWritten "the value's position on its side"
      , MkParameter "axis" positionKind AlwaysWritten "the axis of the value's ranked shape"
      , MkParameter "term" (WiredValue (WiredArray termWire) termsParam) AlwaysWritten
          "the index term the axis's size is, over the function's binders" ]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members = [MkMember OnObjectConst "::idr::Extent" "extent" []]
  , doc = brief "an unknown axis of a signature and the index term its size is"
  }

||| `#idr.extents<[input 0 axis 1 = v0]>`, C++ `ExtentsAttr`: the entries,
||| in increasing order of side, position and axis, none twice. Built by
||| whoever writes or substitutes the terms from entries whose terms live
||| anywhere: the attribute copies them.
export
extentsAttr : AttrDef 1
extentsAttr = MkAttrDef
  { mnemonic = "extents"
  , params =
      [ MkParameter "entries"
          (WiredValue (WiredArray (WireLeaf (LeafAttr "::idr::ExtentAttr")))
                      extentEntriesDirective)
          AlwaysWritten "each unknown axis named by a term, in order of side, position and axis" ]
  , syntax = Declarative [Keyword "<", ParamAt FZ, Keyword ">"]
  , typed = Untyped
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members =
      [ MkMember OnClass "::idr::ExtentsAttr" "get"
          [ param "::mlir::MLIRContext *" "context"
          , param "::llvm::ArrayRef<::idr::Extent>" "entries" ] ]
  , doc = MkDoc "the index term each unknown axis of a function's signature is"
      """
      Each listed axis of an argument or a result is `?` in its type, and its
      size is the listed term over the function's binders. An axis not
      listed is static, or no term names it. Empty in a function that names
      none. Moving the signature's positions keeps it so.
      """
  }
