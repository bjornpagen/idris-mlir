-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The families' declarations in the dialect: the family attribute, the
||| data type a member applied to index terms, a member of a declaration's
||| own group, the binders and terms of a scope, the ops that build, read
||| and refine a constructor value, the interface over the ops that bind
||| index variables, and the constants the C++ reads.
|||
||| A data type is `!idr.data<#Vect[n]>`: identity is content, no table
||| holds it and no name is looked up, so a name without a body cannot be
||| written. A match refines the index (a case binds its scrutinee refined to
||| its constructor, its fields reads of that refined value), a known index
||| fixes the shape, and inline or in a cell is layout, computed from the
||| type when it is made.
module IdrisMLIR.Spec.Families.Dialect

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Families.Terms
import IdrisMLIR.Spec.Families.Group
import IdrisMLIR.Spec.Families.Layout

import Data.Fin
import Data.List.Elem
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The closed sets the C++ storage and the bytecode name
------------------------------------------------------------------------------

export
termKindClosed : Closed TermKind
termKindClosed = MkClosed
  { name = "TermKind"
  , shape = OneOf
  , every = Natural ::: [Level, Successor, Literal, Constructor, Opaque]
  , complete = \case
      Natural => Here
      Level => There Here
      Successor => There (There Here)
      Literal => There (There (There Here))
      Constructor => There (There (There (There Here)))
      Opaque => There (There (There (There (There Here))))
  , describe = \case
      Natural => MkCase "Natural" ("natural" ::: []) "a natural, a number"
      Level => MkCase "Level" ("level" ::: []) "a binder, by its level in its scope"
      Successor => MkCase "Successor" ("successor" ::: []) "a level plus a positive count"
      Literal => MkCase "Literal" ("literal" ::: []) "a constant of a scalar sort, or a type"
      Constructor => MkCase "Constructor" ("constructor" ::: []) "a constructor applied to its binders and fields"
      Opaque => MkCase "Opaque" ("opaque" ::: []) "an index outside the language, which refines nothing"
  , doc = brief "the kinds of node of an index term"
  }

export
sortKindClosed : Closed SortKind
sortKindClosed = MkClosed
  { name = "SortKind"
  , shape = OneOf
  , every = NatSort ::: [TypeSort, OpaqueSort, ScalarSort, FamilySort]
  , complete = \case
      NatSort => Here
      TypeSort => There Here
      OpaqueSort => There (There Here)
      ScalarSort => There (There (There Here))
      FamilySort => There (There (There (There Here)))
  , describe = \case
      NatSort => MkCase "NatSort" ("nat" ::: []) "a natural, or a member whose values are numbers"
      TypeSort => MkCase "TypeSort" ("type" ::: []) "an Idris type, by the MLIR type it is"
      OpaqueSort => MkCase "OpaqueSort" ("opaque" ::: []) "anything else: levels and opaque terms alone"
      ScalarSort => MkCase "ScalarSort" ("scalar" ::: []) "a scalar type, whose literals are its terms"
      FamilySort => MkCase "FamilySort" ("family" ::: []) "a member of a family, whose constructors are its terms"
  , doc = brief "the kinds of sort an index position or a binder has"
  }

export
promiseClosed : Closed Promise
promiseClosed = MkClosed
  { name = "Promise"
  , shape = OneOf
  , every = None ::: [InPlace]
  , complete = \case
      None => Here
      InPlace => There Here
  , describe = \case
      None => MkCase "None" ("none" ::: []) "no promise"
      InPlace => MkCase "InPlace" ("in_place" ::: []) "its values are rebuilt in place with no run-time test"
  , doc = brief "what a data member promises of its values"
  }

export
modeClosed : Closed Mode
modeClosed = MkClosed
  { name = "Mode"
  , shape = OneOf
  , every = Memoized ::: [ByName]
  , complete = \case
      Memoized => Here
      ByName => There Here
  , describe = \case
      Memoized => MkCase "Memoized" ("memoized" ::: []) "run once, its cell then holding the value"
      ByName => MkCase "ByName" ("by_name" ::: []) "run at every force, the cell never written"
  , doc = brief "how a force runs a memo label"
  }

export
memberKindClosed : Closed MemberKind
memberKindClosed = MkClosed
  { name = "MemberKind"
  , shape = OneOf
  , every = Data ::: [Closures, Memo, Frames]
  , complete = \case
      Data => Here
      Closures => There Here
      Memo => There (There Here)
      Frames => There (There (There Here))
  , describe = \case
      Data => MkCase "Data" ("data" ::: []) "Idris's data, its declaration's constructors"
      Closures => MkCase "Closures" ("closures" ::: []) "a closure sum, a label per function"
      Memo => MkCase "Memo" ("memo" ::: []) "a memo sum, its labels then running and forced"
      Frames => MkCase "Frames" ("frames" ::: []) "a frame stack, the frames a recursion pushes"
  , doc = brief "the kinds of member of a family"
  }

export
layoutClosed : Closed Layout
layoutClosed = MkClosed
  { name = "Layout"
  , shape = OneOf
  , every = Word8 ::: [Word16, Word32, Word64, Natural, InPlace, Cell, FrameStack]
  , complete = \case
      Word8 => Here
      Word16 => There Here
      Word32 => There (There Here)
      Word64 => There (There (There Here))
      Natural => There (There (There (There Here)))
      InPlace => There (There (There (There (There Here))))
      Cell => There (There (There (There (There (There Here)))))
      FrameStack => There (There (There (There (There (There (There Here))))))
  , describe = \case
      Word8 => MkCase "Word8" ("word8" ::: []) "a number below 2^8"
      Word16 => MkCase "Word16" ("word16" ::: []) "a number below 2^16"
      Word32 => MkCase "Word32" ("word32" ::: []) "a number below 2^32"
      Word64 => MkCase "Word64" ("word64" ::: []) "a number below 2^64"
      Natural => MkCase "Natural" ("natural" ::: []) "a natural, a big's word"
      InPlace => MkCase "InPlace" ("in_place" ::: []) "its constructors' fields in place, a tag where two are possible"
      Cell => MkCase "Cell" ("cell" ::: []) "one pointer to a cell"
      FrameStack => MkCase "FrameStack" ("frame_stack" ::: []) "the top of a frame stack, linear and uncounted"
  , doc = brief "what a value of a data type is at run time"
  }

export
classClosed : Closed Class
classClosed = MkClosed
  { name = "Class"
  , shape = OneOf
  , every = Closed ::: [Unknown]
  , complete = \case
      Closed => Here
      Unknown => There Here
  , describe = \case
      Closed => MkCase "Closed" ("closed" ::: []) "every index closed and its unfolding within the shape budget"
      Unknown => MkCase "Unknown" ("unknown" ::: []) "an index names a level, holds an opaque term, or unfolds past the budget"
  , doc = brief "whether an application's indices fix its shape"
  }

export
reachClosed : Closed Reach
reachClosed = MkClosed
  { name = "Reach"
  , shape = OneOf
  , every = Bounded ::: [Unbounded]
  , complete = \case
      Bounded => Here
      Unbounded => There Here
  , describe = \case
      Bounded => MkCase "Bounded" ("bounded" ::: []) "everything a value reaches is bounded by its type"
      Unbounded => MkCase "Unbounded" ("unbounded" ::: []) "a value may reach a self-holding member or a cell sized at run time"
  , doc = brief "whether a value's type bounds everything it reaches"
  }

||| The header the families' hand C++ includes: the closed sets above and
||| the shape budget.
export
familiesHeader : Header
familiesHeader = MkHeader "Families"
  [ ( "idr" ::: []
    , [ EnumOf (enumDef termKindClosed), EnumOf (enumDef sortKindClosed)
      , EnumOf (enumDef promiseClosed), EnumOf (enumDef modeClosed)
      , EnumOf (enumDef memberKindClosed), EnumOf (enumDef layoutClosed)
      , EnumOf (enumDef classClosed), EnumOf (enumDef reachClosed)
      , Scalar "shapeBudget" Unsigned32 (IntCell (natToInteger shapeBudget))
          "the most components a closed application unfolds to in place" ] ) ]
  (brief "the families' closed sets and the shape budget")

------------------------------------------------------------------------------
-- What a parameter of ours holds
------------------------------------------------------------------------------

||| Index terms in normal form, `3`, `v1 + 2`, `#List @Cons(v0, v1)`, `_`.
export
termsParam : Directive
termsParam = MkDirective "IndexTerms" [] (brief "index terms in normal form")

||| Sorts, `nat`, `type`, `opaque`, a scalar type, `#G at 1`, `self`.
export
sortsParam : Directive
sortsParam = MkDirective "Sorts" [] (brief "the sorts of index positions or binders")

||| A group's members.
export
membersParam : Directive
membersParam = MkDirective "Members" [] (brief "a family's members and their constructors")

||| A refinement: none, `@C`, `@C<terms>`, or `{@A, @B}`.
export
refinementParam : Directive
refinementParam = MkDirective "Refinement" [] (brief "the constructors a data type is refined to")

||| A family, the group a data type names.
export
familyParam : Directive
familyParam = MkDirective "FamilyRef" [] (brief "a family, by its alias")

||| A data type, a constant's, by its entry.
export
dataParam : Directive
dataParam = MkDirective "DataRef" [] (brief "a data type, by its entry")

termsCode : Code
termsCode = "::llvm::ArrayRef<::idr::families::TermNode>"

------------------------------------------------------------------------------
-- The types and attributes
------------------------------------------------------------------------------

||| `#idr.family<...>`, C++ `FamilyAttr`: a group of members, its storage its
||| content, the facts of the group that need no index computed when it is
||| made (whether it holds itself, each member's shape, numeral descent and
||| what it holds at an unknown index). Its storage is hand C++, since those
||| facts are kept beside its key.
export
familyAttr : AttrDef 1
familyAttr = MkAttrDef
  { mnemonic = "family"
  , params = [MkParameter "members" (HandValue "::llvm::ArrayRef<::idr::families::Member>" membersParam) AlwaysWritten "the group's members, in order"]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = CheckedBy "readFamily"
  , members =
      [ MkMember OnObjectConst "::idr::families::Containment" "containment" []
      , MkMember OnObjectConst "::idr::MemberKind" "memberKind" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::mlir::StringAttr" "label" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::llvm::ArrayRef<::idr::families::Sort>" "indices" [param "uint32_t" "member"]
      , MkMember OnObjectConst "uint32_t" "tagCount" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::idr::families::CtorView" "ctor" [param "uint32_t" "member", param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::std::optional<::idr::Tag>" "tagOf" [param "uint32_t" "member", param "::llvm::StringRef" "label"]
      , MkMember OnObjectConst "::idr::Promise" "promise" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::idr::families::Shape" "shape" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::std::optional<::idr::families::Descent>" "descent" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::std::optional<::idr::families::ListShape>" "listShape" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::std::optional<::idr::families::MemoView>" "memo" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::std::optional<::idr::families::ClosuresView>" "closures" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::idr::Refs" "refsAtUnknown" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::idr::Reach" "reachAtUnknown" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::llvm::ArrayRef<::idr::families::FieldRef>" "inPlaceFields" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::llvm::ArrayRef<::idr::families::MemberRef>" "selfCells" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::mlir::FlatSymbolRefAttr" "labelFunction" [param "uint32_t" "member", param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::std::optional<::idr::Mode>" "labelMode" [param "uint32_t" "member", param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "bool" "holdsFrames" []
      , MkMember OnObjectConst "bool" "namesLabels" []
      , MkMember OnObjectConst "::std::string" "aliasName" []
      , MkMember OnClass "::mlir::AbstractAttribute::WalkImmediateSubElementsFn" "getWalkImmediateSubElementsFn" []
      , MkMember OnClass "::mlir::AbstractAttribute::ReplaceImmediateSubElementsFn" "getReplaceImmediateSubElementsFn" [] ]
  , doc = MkDoc "a family's declaration: a group of members, by content"
      """
      Each member is Idris's data, a closure sum, a memo sum or a frame
      stack, with its index sorts and its constructors, each with the index
      variables it binds, the equation its result satisfies and its fields.
      A member names another of its group by position, so the attribute is
      acyclic. Labels are part of its identity and nothing looks one up.
      """
  }

||| `!idr.data<#F[ts]>`, C++ `DataType`: a member applied to index terms,
||| perhaps refined to fewer constructors. Its storage is hand C++: its
||| possible constructors, class, layout and references are computed when it
||| is made and kept beside its key.
export
dataType : TypeDef 5
dataType = MkTypeDef
  { mnemonic = "data"
  , params =
      [ MkParameter "group" (HandValue "::idr::FamilyAttr" familyParam) AlwaysWritten "the family"
      , MkParameter "member" CountValue AlwaysWritten "the member of the family"
      , MkParameter "indices" (HandValue termsCode termsParam) AlwaysWritten "one term per index"
      , MkParameter "refinement" (HandValue "::mlir::DenseI32ArrayAttr" refinementParam) (DefaultsTo "{}") "the tags of the constructors it is refined to, ascending; none unrefined, empty uninhabited"
      , MkParameter "binders" (HandValue termsCode termsParam) (DefaultsTo "{}") "its one constructor's undetermined binders" ]
  , syntax = HandSyntax
  , interfaces = [Declares MemRefElementType []]
  , verifier = VerifiesParameters
  , bytecode = CheckedBy "readDataType"
  , members =
      [ MkMember OnClass "::idr::DataType" "get" [param "::mlir::MLIRContext *" "context", param "::idr::FamilyAttr" "group", param "uint32_t" "member", param termsCode "indices"]
      , MkMember OnClass "::idr::DataType" "getNormalized" [param "::llvm::function_ref<::mlir::InFlightDiagnostic()>" "emitError", param "::idr::FamilyAttr" "group", param "uint32_t" "member", param termsCode "indices", param "::mlir::DenseI32ArrayAttr" "refinement", param termsCode "binders"]
      , MkMember OnObjectConst "::idr::DataType" "refined" [param "::llvm::ArrayRef<::idr::Tag>" "tags"]
      , MkMember OnObjectConst "::idr::DataType" "refinedTo" [param "::idr::Tag" "tag", param termsCode "binders"]
      , MkMember OnObjectConst "::idr::DataType" "unrefined" []
      , MkMember OnObjectConst "const ::idr::families::TagSet &" "possibleTags" []
      , MkMember OnObjectConst "::std::optional<::idr::Tag>" "singleTag" []
      , MkMember OnObjectConst "uint32_t" "declaredCount" []
      , MkMember OnObjectConst "::idr::MemberKind" "kind" []
      , MkMember OnObjectConst "::idr::families::CtorView" "ctor" [param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::llvm::ArrayRef<::idr::families::Sort>" "binderSorts" [param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::std::optional<::idr::families::MemoView>" "memo" []
      , MkMember OnObjectConst "::std::optional<::idr::families::ClosuresView>" "closures" []
      , MkMember OnObjectConst "::std::optional<::idr::families::ListShape>" "listShape" []
      , MkMember OnObjectConst "::idr::Promise" "promise" []
      , MkMember OnObjectConst "::mlir::FlatSymbolRefAttr" "labelFunction" [param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::std::optional<::idr::Mode>" "labelMode" [param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::idr::Layout" "layout" []
      , MkMember OnObjectConst "::idr::Class" "cls" []
      , MkMember OnObjectConst "uint32_t" "components" []
      , MkMember OnObjectConst "bool" "boundsReach" []
      , MkMember OnObjectConst "::llvm::ArrayRef<::idr::families::FieldRef>" "inPlaceFields" []
      , MkMember OnObjectConst "::llvm::ArrayRef<::idr::families::MemberRef>" "selfCells" []
      , MkMember OnObjectConst "uint32_t" "freeLevels" []
      , MkMember OnObjectConst "::std::optional<::llvm::SmallVector<::idr::families::TermNode>>" "bindersOf" [param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::std::optional<::llvm::SmallVector<::mlir::Type>>" "determinedFields" [param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "bool" "holdsReferences" []
      , MkMember OnObjectConst "bool" "isLinearByType" []
      , MkMember OnObjectConst "bool" "isCounted" []
      , MkMember OnObjectConst "bool" "isCellPointer" [] ]
  , doc = MkDoc "a data type: a member of a family applied to index terms"
      """
      Written `!idr.data<#Vect[v0]>`, `!idr.data<#Tree at 1 [v0]>`, refined
      `!idr.data<#List @Cons>`, `!idr.data<#T {@A, @B}>`, or `!idr.data<#Ex
      @MkEx<v3>>` where its constructor binds an index variable its indices
      do not determine. Identity is content. Its class, layout and what it
      holds are computed when it is made.
      """
  }

||| `!idr.self at m [ts]`, C++ `SelfType`: a member of the group a field is
||| declared in, by position, legal only inside a declaration; a field read
||| of it gives the member's data type.
export
selfType : TypeDef 2
selfType = MkTypeDef
  { mnemonic = "self"
  , params =
      [ MkParameter "member" CountValue AlwaysWritten "the member of the group being declared"
      , MkParameter "indices" (HandValue termsCode termsParam) AlwaysWritten "one term per index, over the constructor's binders" ]
  , syntax = HandSyntax
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = CheckedBy "readSelf"
  , members = []
  , doc = brief "a member of the group a field is declared in, by position"
  }

||| `#idr.index_binders<[nat, ...]>`, C++ `IndexBindersAttr`: the sorts of
||| the index variables a function, a join region or a constructor binds, at
||| the next levels of its scope.
export
indexBindersAttr : AttrDef 1
indexBindersAttr = MkAttrDef
  { mnemonic = "index_binders"
  , params = [MkParameter "sorts" (HandValue "::llvm::ArrayRef<::idr::families::Sort>" sortsParam) AlwaysWritten "the binders' sorts, in level order"]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = CheckedBy "readIndexBinders"
  , members = []
  , doc = brief "the sorts of the index variables a scope binds"
  }

||| `#idr.index_args<[3, v0, _]>`, C++ `IndexArgsAttr`: the terms a call or
||| a jump gives its target's index variables, in the caller's scope.
export
indexArgsAttr : AttrDef 2
indexArgsAttr = MkAttrDef
  { mnemonic = "index_args"
  , params =
      [ MkParameter "terms" (HandValue termsCode termsParam) AlwaysWritten "the terms, one after the other"
      , MkParameter "count" CountValue AlwaysWritten "how many terms" ]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = CheckedBy "readIndexArgs"
  , members = []
  , doc = brief "the terms a call or a jump gives its target's index variables"
  }

||| `#idr.equation<lhs = rhs>`, C++ `EquationAttr`: an erased equality's two
||| index terms, which `idr.index.assume` assumes in its region.
export
equationAttr : AttrDef 2
equationAttr = MkAttrDef
  { mnemonic = "equation"
  , params =
      [ MkParameter "lhs" (HandValue termsCode termsParam) AlwaysWritten "the left term"
      , MkParameter "rhs" (HandValue termsCode termsParam) AlwaysWritten "the right term" ]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = CheckedBy "readEquation"
  , members = []
  , doc = brief "an erased equality between two index terms"
  }

||| `#idr.con<!T, [fields]>`, C++ `ConAttr`: a constant constructor value,
||| its data type refined to the constructor, held as a run of its cells so
||| that a constant as long as the data it is stays one level deep to MLIR's
||| printer, parser, bytecode and walks: a plain constructor is one cell; a
||| chain of one constructor through one field is the run of its cells,
||| every one but the last without the field the next one is. Not of a memo
||| cell or of a family rebuilt in place, each of which is its own value.
export
conAttr : AttrDef 3
conAttr = MkAttrDef
  { mnemonic = "con"
  , params =
      [ MkParameter "data" (HandValue "::idr::DataType" dataParam) AlwaysWritten "the data type, refined to the constructor"
      , MkParameter "cells" (ListOf AttrValue) AlwaysWritten "the cells, each an array of its fields, every one but the last without the spine"
      , MkParameter "spine" CountValue (DefaultsTo "0") "the field a run runs along" ]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = CheckedBy "readCon"
  , members =
      [ MkMember OnClass "::idr::ConAttr" "get" [param "::mlir::MLIRContext *" "context", param "::idr::DataType" "data", param "::mlir::ArrayAttr" "fields"]
      , MkMember OnClass "::idr::ConAttr" "getRun" [param "::mlir::MLIRContext *" "context", param "::idr::DataType" "data", param "unsigned" "spine", param "::llvm::ArrayRef<::mlir::ArrayAttr>" "cells"]
      , MkMember OnClass "::idr::ConAttr" "getNormalized" [param "::llvm::function_ref<::mlir::InFlightDiagnostic()>" "emitError", param "::mlir::MLIRContext *" "context", param "::idr::DataType" "data", param "::llvm::ArrayRef<::mlir::Attribute>" "cells", param "uint64_t" "spine"]
      , MkMember OnObjectConst "::idr::Tag" "getTag" []
      , MkMember OnObjectConst "unsigned" "getRunLength" []
      , MkMember OnObjectConst "::mlir::ArrayAttr" "getCell" [param "unsigned" "cell"]
      , MkMember OnObjectConst "unsigned" "fieldOfCell" [param "unsigned" "cell", param "unsigned" "position"]
      , MkMember OnObjectConst "void" "walkFields" [param "::llvm::function_ref<void(::mlir::Attribute, unsigned)>" "each"]
      , MkMember OnObjectConst "::mlir::Attribute" "getField" [param "unsigned" "index"]
      , MkMember OnObjectConst "::mlir::ArrayAttr" "getFields" [] ]
  , doc = brief "a constant constructor value, a run of its cells"
  }

||| The slot a function takes its binders in, and a call or jump its terms.
export
indexBinders : AttrKind
indexBinders = AnAttribute (OurAttr (SomeAttr indexBindersAttr))
  (DefaultValued "::idr::IndexBindersAttr::get($_builder.getContext(), {})")

export
indexArgs : AttrKind
indexArgs = AnAttribute (OurAttr (SomeAttr indexArgsAttr))
  (DefaultValued "::idr::IndexArgsAttr::get($_builder.getContext(), {}, 0)")

------------------------------------------------------------------------------
-- What an operand of ours is
------------------------------------------------------------------------------

||| A value of a data type, at any grade: what a match takes apart and a tag
||| reads.
export
dataValue : Predicate
dataValue = MkPredicate "isDataValue" OnType (brief "a value of a data type, at any grade")

||| A value of a data type refined to one constructor whose binders it
||| determines, at any grade: what a field is a total read of.
export
refinedValue : Predicate
refinedValue = MkPredicate "isRefinedValue" OnType
  (brief "a value of a data type refined to one constructor, at any grade")

||| A value whose layout is a cell, at any grade: the only values counting's
||| ops take and a destination writes.
export
cellValue : Predicate
cellValue = MkPredicate "isCellValue" OnType (brief "a value of a data type held in a cell")

||| A value of a numeral family, whose layout is a number.
export
numeralValue : Predicate
numeralValue = MkPredicate "isNumeralValue" OnType (brief "a value of a family of numeral shape")

||| A natural, at any grade.
export
naturalValue : Predicate
naturalValue = MkPredicate "isNaturalValue" OnType (brief "a natural, at any grade")

------------------------------------------------------------------------------
-- The interface over the ops that bind index variables
------------------------------------------------------------------------------

||| `ErasedBinderOpInterface`: the sorts of the index variables a region of
||| the op binds, at the next levels of the scope (a function's binders, a
||| case's constructor's, a join region's), and what equation the region
||| assumes (a case's constructor's equation against its scrutinee's
||| indices, an assumed equality), which the function's scope walk unifies
||| as it enters the region. Every binder of the IR is read through it.
export
erasedBinderInterface : InterfaceDef
erasedBinderInterface = MkInterfaceDef
  { name = "ErasedBinderOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject "::llvm::ArrayRef<::idr::families::Sort>" "getBoundSorts"
          [param "::mlir::Region &" "region"] EveryImplementer
          "the sorts of the index variables `region` binds, at the next levels"
      , MkMethod PerObject "::std::optional<::idr::families::RegionRefinement>" "getRefinement"
          [param "::mlir::Region &" "region"] (Delegates "noRefinement")
          "the equation `region` assumes as it is entered, none where it assumes none" ]
  , verifier = Unverified
  , doc = brief "an op whose regions bind index variables or assume an equation of them"
  }

------------------------------------------------------------------------------
-- The ops' custom directives
------------------------------------------------------------------------------

||| `(%a : A, %b : B)`: the fields a constructor value is given.
export
fieldsDirective : Directive
fieldsDirective = MkDirective "Fields" [VariadicOperandArg, VariadicTypeArg]
  (brief "the fields a constructor value is given, each with its type")

||| `(%a : A, dest, %b : B)`: the fields a cell's init writes, a hole as
||| `dest`.
export
fieldsWithHolesDirective : Directive
fieldsWithHolesDirective = MkDirective "FieldsWithHoles"
  [VariadicOperandArg, VariadicTypeArg, AttrArg "::mlir::DenseI32ArrayAttr"]
  (brief "the fields a cell's init writes, and its holes")

||| A dup's result: counted unless another grade is written.
export
countedResultDirective : Directive
countedResultDirective = MkDirective "CountedResult" [TypeArg, RefTypeArg]
  (brief "a dup's result, counted unless written")

------------------------------------------------------------------------------
-- The ops
------------------------------------------------------------------------------

||| `idr.data.con`: a constructor value, every field given. Its constructor is
||| the one its refined result type leaves possible, so no tag stands beside
||| the type. Building an immutable value acquires nothing before counting,
||| so two equal ones are one and an unused one goes; a result whose identity
||| is read (used once, of a family rebuilt in place, or an unforced memo
||| cell) is a fresh identity, never merged.
export
conOp : Op 1 1 0 0
conOp = MkOp
  { home = InIdr
  , mnemonic = "data.con"
  , ins = [variadic "fields" (UpstreamType AnyTypeC)]
  , outs = [result "result" (SatisfiesType refinedValue)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = Executes [] [NewIdentity 0] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared
      [ Custom fieldsDirective [Group (OperandRef 0), TypeOfGroup (OperandRef 0)]
      , AttrDict, Lit ":", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members =
      [ MkMember OnObject "::idr::DataType" "getDataType" []
      , MkMember OnObject "::idr::Tag" "getTag" [] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "builds a constructor value"
      """
      `idr.data.con(%x : i64, %xs : !idr.data<#List>) : !idr.data<#List @Cons>`:
      the fields, then the value's type, refined to its constructor.
      """
  }

||| `idr.data.field`: field `index` of a value refined to one constructor, read
||| at the value's uses times the field's, as a match binds it: a total read,
||| since the type fixes the constructor, so it may run anywhere its operand
||| is. A memo cell's field reads its state, which a force writes.
export
fieldOp : Op 1 1 1 0
fieldOp = MkOp
  { home = InIdr
  , mnemonic = "data.field"
  , ins = [single "value" (SatisfiesType refinedValue)]
  , outs = [result "result" (UpstreamType AnyTypeC)]
  , attrs = [attr "index" (UpstreamAttr I64AttrC)]
  , regions = []
  , traits = []
  , interfaces = []
  , effects = Executes [] [ReadsMemo 0] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "[", ValueOf (AttrRef 0), Lit "]", AttrDict
      , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = [MkBuilder [param "::mlir::Value" "value", param "unsigned" "index"]]
  , defaultBuilders = WithDefaults
  , members =
      [ MkMember OnObject "::idr::DataType" "getDataType" []
      , MkMember OnObject "::idr::Tag" "getTag" [] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "reads a field of a value refined to its constructor"
  }

||| `idr.data.tag`: the constructor of a data value, in [0, n-1] for its n
||| declared constructors; it folds where the type leaves one possible.
export
tagOp : Op 1 1 0 0
tagOp = MkOp
  { home = InIdr
  , mnemonic = "data.tag"
  , ins = [single "value" (SatisfiesType dataValue)]
  , outs = [result "result" (UpstreamType I64C)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = Executes [] [ReadsMemo 0] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = DeclarationOnly
  , format = Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "the constructor tag of a data value"
  }

||| `idr.data.reindex`: the same value at a type equal to its own under the
||| refinements of the enclosing scopes (a case's equation, an assumed
||| equality), or a refined data type given where its unrefined one is
||| asked. Pure; free where the two layouts are equal, a bounded re-pack
||| where an index known inside a function changes the layout. Checked by
||| the function's scope walk, which holds the refinements.
export
dataReindexOp : Op 1 1 0 0
dataReindexOp = MkOp
  { home = InIdr
  , mnemonic = "data.reindex"
  , ins = [single "value" (UpstreamType AnyTypeC)]
  , outs = [result "result" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares Speculatable ["getSpeculatability"]]
  , effects = noEffects
  , speculation = Conditionally
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
      , Lit "to", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a value at a type its enclosing refinements make equal to its own"
  }

||| `idr.index.assume`: a region in which an erased equality Idris proved holds
||| (`replace`, `rewrite`, a match on an erased `Refl`), the values whose
||| types mention its terms forwarded into it refined. The one place a fact
||| enters the IR on Idris's word alone; inside it, every cast is checked as
||| any other. An equality that clashes makes the region unreachable.
export
assumeOp : Op 1 1 1 1
assumeOp = MkOp
  { home = InIdr
  , mnemonic = "index.assume"
  , ins = [variadic "forwarded" (UpstreamType AnyTypeC)]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = [attr "equation" (OurAttr (SomeAttr equationAttr))]
  , regions = [sized "body" 1]
  , traits = [SingleBlock, PropagateControlFlowBreak]
  , interfaces =
      [ Declares RegionBranch ["getSuccessorRegions", "getEntrySuccessorOperands", "areTypesCompatible"]
      , Implements erasedBinderInterface ["getBoundSorts", "getRefinement"] ]
  , effects = Executes [] [] Recursive Untouched
  , speculation = RecursivelySpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = VerifiesOp
  , format = HandFormat
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a region in which an erased equality of index terms holds"
  }

||| `idr.numeral.to_nat`: a numeral's value as a natural: the identity at a
||| natural's layout, a widening at a fixed width.
export
numeralToNatOp : Op 1 1 0 0
numeralToNatOp = MkOp
  { home = InIdr
  , mnemonic = "numeral.to_nat"
  , ins = [single "value" (SatisfiesType numeralValue)]
  , outs = [result "result" (SatisfiesType naturalValue)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = noEffects
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
      , Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a numeral's value as a natural"
  }

||| `idr.numeral.of_nat`: a natural as a numeral of the bound Idris proved
||| it below, with no range check: a narrowing at a fixed width.
export
numeralOfNatOp : Op 1 1 0 0
numeralOfNatOp = MkOp
  { home = InIdr
  , mnemonic = "numeral.of_nat"
  , ins = [single "value" (SatisfiesType naturalValue)]
  , outs = [result "result" (SatisfiesType numeralValue)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = noEffects
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
      , Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a natural as a numeral, with no range check"
  }

------------------------------------------------------------------------------
-- The rules that rewrite the ops above
------------------------------------------------------------------------------

||| A field of a value an `idr.data.con` built is the field it was given; a
||| constructor rebuilt from every field of a value refined to it is that
||| value (record eta), except where its result's identity is read. Each
||| reads a variadic group by position, so each is a skeleton rule.
export
familySkeleton : List SkeletonRule
familySkeleton =
  [ MkSkeletonRule "FieldOfCon" "data.field" "a field of a value idr.data.con built is the field it was given"
  , MkSkeletonRule "ConEta" "data.con" "a constructor rebuilt from every field of a value refined to it is that value" ]
