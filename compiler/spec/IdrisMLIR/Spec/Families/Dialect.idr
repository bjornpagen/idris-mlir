-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The families' vocabulary in the dialect: the closed sets the C++ storage
||| and the bytecode name, what a parameter of ours holds, the binders and
||| terms of a scope, the interface over the ops that bind index variables,
||| and the ops' directives. The family attribute and the data type are
||| `Spec.Families.Types`'s, the ops that build, read and refine a
||| constructor value `Spec.Families.Ops`'s.
|||
||| A data type is `!idr.data<#Vect[n]>`: identity is content, no table
||| holds it and no name is looked up, so a name without a body cannot be
||| written. A match refines the index (a case binds its scrutinee refined to
||| its constructor, its fields reads of that refined value), a known index
||| fixes the shape, and inline or in a cell is layout, computed from the
||| type when it is made.
module IdrisMLIR.Spec.Families.Dialect

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Families.Terms
import IdrisMLIR.Spec.Families.Group
import IdrisMLIR.Spec.Families.Layout

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

export
buffersClosed : Closed Buffers
buffersClosed = MkClosed
  { name = "Buffers"
  , shape = OneOf
  , every = NoBuffer ::: [HoldsBuffer]
  , complete = \case
      NoBuffer => Here
      HoldsBuffer => There Here
  , describe = \case
      NoBuffer => MkCase "NoBuffer" ("no_buffer" ::: []) "no cell the claim on its own cells covers holds a buffer"
      HoldsBuffer => MkCase "HoldsBuffer" ("holds_buffer" ::: []) "a cell the claim on its own cells covers holds a buffer"
  , doc = brief "whether a member's own cells hold a buffer"
  }

export
closureReachClosed : Closed ClosureReach
closureReachClosed = MkClosed
  { name = "ClosureReach"
  , shape = OneOf
  , every = NoClosure ::: [ReachesClosure]
  , complete = \case
      NoClosure => Here
      ReachesClosure => There Here
  , describe = \case
      NoClosure => MkCase "NoClosure" ("no_closure" ::: []) "no value of the family reaches a closure or a suspension"
      ReachesClosure => MkCase "ReachesClosure" ("reaches_closure" ::: []) "a value of the family can reach a closure or a suspension"
  , doc = brief "whether a family's values can reach a closure or a suspension"
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
      , EnumOf (enumDef buffersClosed), EnumOf (enumDef closureReachClosed)
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

||| Index terms as a parameter holds them: an array of nodes, read into the
||| vector that owns them, which the storage copies.
export
termArray : Directive -> ParamKind
termArray = HandArray "::idr::families::TermNode"

||| Index terms as a C++ member takes them.
export
termsCode : Code
termsCode = "::llvm::ArrayRef<::idr::families::TermNode>"

------------------------------------------------------------------------------
-- The binders and terms of a scope
------------------------------------------------------------------------------

||| `#idr.index_binders<[nat, ...]>`, C++ `IndexBindersAttr`: the sorts of
||| the index variables a function, a join region or a constructor binds, at
||| the next levels of its scope.
export
indexBindersAttr : AttrDef 1
indexBindersAttr = MkAttrDef
  { mnemonic = "index_binders"
  , params = [MkParameter "sorts" (HandArray "::idr::families::Sort" sortsParam) AlwaysWritten "the binders' sorts, in level order"]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = CheckedBy "readIndexBinders"
  , storage = HandStorage
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
      [ MkParameter "terms" (termArray termsParam) AlwaysWritten "the terms, one after the other"
      , MkParameter "count" CountValue AlwaysWritten "how many terms" ]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = CheckedBy "readIndexArgs"
  , storage = HandStorage
  , members = []
  , doc = brief "the terms a call or a jump gives its target's index variables"
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
