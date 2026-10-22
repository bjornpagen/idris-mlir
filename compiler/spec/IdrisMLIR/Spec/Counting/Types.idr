-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Counting's types: the memory a constructor is built in, and the reuse
||| token. Apart from counting's ops, so the lifetimes' cell sources, which
||| give a cell, read them with no cycle between the two areas.
module IdrisMLIR.Spec.Counting.Types

import IdrisMLIR.Spec.Core.Vocabulary

import Data.Fin
import Data.Vect

%default total

||| `!idr.cell<T>`, C++ `CellType`: the memory of one cell of the
||| constructor `T` is refined to, its header written, its fields not yet. It
||| holds no reference until its init writes the fields, and its one use is
||| that init, as its type alone says; a constructor that is an atom has no
||| cell, so no cell type names one. `getData` and `getTag` read `T` as the
||| data type and the constructor.
export
cellType : TypeDef 1
cellType = MkTypeDef
  { mnemonic = "cell"
  , params =
      [ MkParameter "value" TypeValue AlwaysWritten
          "the value the cell holds once filled: a data type refined to one constructor" ]
  , syntax = Declarative [Keyword "<", ParamAt 0, Keyword ">"]
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members =
      [ MkMember OnObjectConst "::idr::DataType" "getData" []
      , MkMember OnObjectConst "::idr::Tag" "getTag" [] ]
  , facts = Answers (MkValueFacts HoldsNoReference UsedOnceByType Uncounted AlwaysCell)
  , doc = brief "the memory of one cell of a constructor, its header written, its fields not yet"
  }

||| `!idr.token<{T, ...}>`, C++ `TokenType`: the memory of a cell whose
||| fields a take moved out, to be recycled into a construction of its size
||| or freed. Its parameter is the non-empty set of data types, each refined
||| to one constructor, whose cell it may be, all of one size: a take gives
||| a set of one, a rejoin the union of what its paths give, so the type
||| keeps exactly what every path knows. Its size is derived from any member
||| and the target's layout, never stored beside it. Used once, graded
||| `counted unique deep` (it holds its cell, never null) or `counted` (null
||| where its take found the cell shared).
export
tokenType : TypeDef 1
tokenType = MkTypeDef
  { mnemonic = "token"
  , params =
      [ MkParameter "sources" (ListOf TypeValue) AlwaysWritten
          "the data types refined to one constructor whose cell it may be" ]
  , syntax = Declarative [Keyword "<", Keyword "{", ParamAt 0, Keyword "}", Keyword ">"]
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = Derived
  , members =
      [ MkMember OnClass "::idr::TokenType" "of" [param "::idr::DataType" "source"]
      , MkMember OnClass "::idr::TokenType" "merged" [param "::llvm::ArrayRef<::idr::TokenType>" "tokens"] ]
  , facts = Answers (MkValueFacts HoldsReferences UsedAsGraded Counted MayBeOtherWord)
  , doc = brief "the memory of a cell whose fields a take moved out, or null"
  }
