-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The families' types and the attributes that hold their values: the
||| family attribute, a group of members by content; the data type, a member
||| applied to index terms; a member of a declaration's own group by
||| position; an erased equality of index terms; and a constructor constant.
||| Each storage is hand C++, since what a family or a data type is at run
||| time is computed when it is made and kept beside its key.
module IdrisMLIR.Spec.Families.Types

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Families.Group
import IdrisMLIR.Spec.Families.Layout

import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- How bytecode lays out a family's members
------------------------------------------------------------------------------

||| Where the frontend finds the closed sets a member holds a case of.
promiseCase : ImportedEnum
promiseCase = imported promiseClosed
  (MkSource ("IdrisMLIR" ::: ["Spec", "Families", "Group"]) "Promise"
            ("IdrisMLIR" ::: ["Spec", "Families", "Dialect"]) "promiseClosed")

||| Where the frontend finds the mark a data type's layout reads.
markCase : ImportedEnum
markCase = imported layoutMarkClosed
  (MkSource ("IdrisMLIR" ::: ["Spec", "Families", "Layout"]) "LayoutMark"
            ("IdrisMLIR" ::: ["Spec", "Families", "Layout"]) "layoutMarkClosed")

modeCase : ImportedEnum
modeCase = imported modeClosed
  (MkSource ("IdrisMLIR" ::: ["Spec", "Families", "Group"]) "Mode"
            ("IdrisMLIR" ::: ["Spec", "Families", "Dialect"]) "modeClosed")

labelField : WireField
labelField = MkWireField "label" (WireLeaf LeafLabel)

indicesField : WireField
indicesField = MkWireField "indices" (WireArray sortWire)

||| What a constructor and a label share: the sorts of the index variables
||| it binds, its equation's terms and its field types.
bodyFields : List WireField
bodyFields =
  [ MkWireField "binders" (WireArray sortWire), MkWireField "equation" (WireArray termWire)
  , MkWireField "fields" (WireArray (WireLeaf (LeafType "::mlir::Type"))) ]

ctorDecl : Composite
ctorDecl = MkComposite "CtorDecl" "::idr::families::CtorDecl" (Fields (labelField :: bodyFields))
  (brief "a constructor of a data member or a frame stack")

labelDecl : Composite
labelDecl = MkComposite "LabelDecl" "::idr::families::LabelDecl"
  (Fields (labelField :: MkWireField "fn" (WireLeaf (LeafAttr "::mlir::FlatSymbolRefAttr")) :: bodyFields))
  (brief "a label of a closure or memo sum, its fields its function's captures")

memoLabelDecl : Composite
memoLabelDecl = MkComposite "MemoLabelDecl" "::idr::families::MemoLabelDecl"
  (Fields [MkWireField "mode" (WireLeaf (LeafCase modeCase)), MkWireField "label" (WireOf labelDecl)])
  (brief "a label of a memo sum, and how a force runs it")

||| Each kind of member, the alternative it is in its sum.
memberBody : MemberKind -> Composite
memberBody Data = MkComposite "DataMember" "::idr::families::DataMember"
  (Fields [ labelField, MkWireField "promise" (WireLeaf (LeafCase promiseCase))
          , MkWireField "loc" (WireLeaf (LeafAttr "::mlir::LocationAttr")), indicesField
          , MkWireField "ctors" (WireArray (WireOf ctorDecl)) ])
  (brief "Idris's data, its declaration's constructors")
memberBody Closures = MkComposite "ClosuresMember" "::idr::families::ClosuresMember"
  (Fields [labelField, indicesField, MkWireField "labels" (WireArray (WireOf labelDecl))])
  (brief "a closure sum, a label per function")
memberBody Memo = MkComposite "MemoMember" "::idr::families::MemoMember"
  (Fields [ labelField, indicesField, MkWireField "labels" (WireArray (WireOf memoLabelDecl))
          , MkWireField "forced" (WireLeaf (LeafType "::mlir::Type")) ])
  (brief "a memo sum, its labels then running and forced")
memberBody Frames = MkComposite "FramesMember" "::idr::families::FramesMember"
  (Fields [labelField, MkWireField "ctors" (WireArray (WireOf ctorDecl))])
  (brief "a frame stack, the frames a recursion pushes")

||| A member on the wire: its kind, then that kind's member.
memberWire : Wire
memberWire = WireOf (MkComposite "MemberOf" "::idr::families::Member"
  (variant memberKindClosed memberBody) (brief "a member of a family, its alternative its kind"))

------------------------------------------------------------------------------
-- The types and attributes
------------------------------------------------------------------------------

||| `#idr.family<...>`, C++ `FamilyAttr`: a group of members, its storage its
||| content, the facts of the group that need no index computed when it is
||| made (whether it holds itself, each member's shape, numeral descent and
||| what it holds at an unknown index, and whether its values can reach a
||| closure or a suspension). Its storage is hand C++, since those
||| facts are kept beside its key. Its members are one value, not an array:
||| a member views arrays of its own (constructors, binders, fields), which
||| no flat vector of members owns, so their reader makes the family, which
||| copies every array once.
export
familyAttr : AttrDef 1
familyAttr = MkAttrDef
  { mnemonic = "family"
  , params = [MkParameter "members" (WiredValue (WiredArray memberWire) membersParam) AlwaysWritten "the group's members, in order"]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = VerifiesParameters
  , bytecode = CheckedBy "readFamily"
  , storage = HandStorage
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
      , MkMember OnObjectConst "::idr::Buffers" "ownBuffers" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::llvm::ArrayRef<::idr::families::MemberRef>" "selfCells" [param "uint32_t" "member"]
      , MkMember OnObjectConst "::mlir::FlatSymbolRefAttr" "labelFunction" [param "uint32_t" "member", param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::std::optional<::idr::Mode>" "labelMode" [param "uint32_t" "member", param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::idr::ClosureReach" "closureReach" []
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
||| perhaps refined to fewer constructors, laid out as its indices say or,
||| marked open, as at an unknown index. Its storage is hand C++: its
||| possible constructors, class, layout, references and words, and a
||| numeral's largest value where its layout is a fixed width, are computed
||| when it is made and kept beside its key. What a value of it holds depends
||| on that layout, so its value facts are a hand unit's answers, read from
||| what was computed, and it declares no constant answers. The frontend
||| writes every type laid out as its indices say; only the specializer
||| opens one, for a tail call whose caller lays its result out so.
export
dataType : TypeDef 6
dataType = MkTypeDef
  { mnemonic = "data"
  , params =
      [ MkParameter "group" (WiredValue (WiredOne (LeafAttr "::idr::FamilyAttr")) familyParam) AlwaysWritten "the family"
      , MkParameter "member" memberPositionKind AlwaysWritten "the member of the family"
      , MkParameter "indices" (WiredValue (WiredArray termWire) termsParam) AlwaysWritten "one term per index"
      , MkParameter "refinement" (WiredValue (WiredOne (LeafMaybeAttr "::mlir::DenseI32ArrayAttr")) refinementParam) (DefaultsTo "{}") "the tags of the constructors it is refined to, ascending; none unrefined, empty uninhabited"
      , MkParameter "binders" (WiredValue (WiredArray termWire) termsParam) (DefaultsTo "{}") "its one constructor's undetermined binders"
      , MkParameter "mark" (EnumValue markCase) (DefaultsTo "::idr::LayoutMark::ByIndices") "how its values are laid out: as its indices say, or open, as at an unknown index" ]
  , syntax = HandSyntax
  , interfaces =
      [ Declares MemRefElementType []
      , Implements indexedTypeInterface ["getIndexTermRuns", "getFreeLevels", "scopeHoldsParts"]
      , Implements patternTypeInterface ["matchInstance"]
      , Implements fieldTypeInterface ["getFieldReach"]
      , Implements numericTypeInterface ["getNumericReading", "isCarriedAsBig"]
      , Implements indexPositionsInterface ["appendIndexPositions", "atFreshPositions"] ]
  , verifier = VerifiesParameters
  , bytecode = CheckedBy "readDataType"
  , storage = HandStorage
  , members =
      [ MkMember OnClass "::idr::DataType" "get" [param "::mlir::MLIRContext *" "context", param "::idr::FamilyAttr" "group", param "uint32_t" "member", param termsCode "indices"]
      , MkMember OnClass "::idr::DataType" "getNormalized" [param "::llvm::function_ref<::mlir::InFlightDiagnostic()>" "emitError", param "::idr::FamilyAttr" "group", param "uint32_t" "member", param termsCode "indices", param "::mlir::DenseI32ArrayAttr" "refinement", param termsCode "binders", param "::idr::LayoutMark" "mark"]
      , MkMember OnObjectConst "::idr::DataType" "marked" [param "::idr::LayoutMark" "mark"]
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
      , MkMember OnObjectConst "::idr::Unique" "promisedClaim" []
      , MkMember OnObjectConst "::mlir::FlatSymbolRefAttr" "labelFunction" [param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::std::optional<::idr::Mode>" "labelMode" [param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::idr::Layout" "layout" []
      , MkMember OnObjectConst "::idr::Class" "cls" []
      , MkMember OnObjectConst "uint32_t" "components" []
      , MkMember OnObjectConst "const ::idr::families::Slots &" "slots" []
      , MkMember OnObjectConst "::std::optional<uint64_t>" "numeralBound" []
      , MkMember OnObjectConst "::idr::LayoutMatch" "layoutMatch" [param "::idr::DataType" "other"]
      , MkMember OnObjectConst "bool" "boundsReach" []
      , MkMember OnObjectConst "::llvm::ArrayRef<::idr::families::MemberRef>" "selfCells" []
      , MkMember OnObjectConst "uint32_t" "freeLevels" []
      , MkMember OnObjectConst "::std::optional<::llvm::SmallVector<::idr::families::TermNode>>" "bindersOf" [param "::idr::Tag" "tag"]
      , MkMember OnObjectConst "::std::optional<::llvm::SmallVector<::mlir::Type>>" "determinedFields" [param "::idr::Tag" "tag"] ]
  , facts = HandAnswers
  , doc = MkDoc "a data type: a member of a family applied to index terms"
      """
      Written `!idr.data<#Vect[v0]>`, `!idr.data<#Tree at 1 [v0]>`, refined
      `!idr.data<#List @Cons>`, `!idr.data<#T {@A, @B}>`, or `!idr.data<#Ex
      @MkEx<v3>>` where its constructor binds an index variable its indices
      do not determine; `!idr.data<#Vect[4] open>` laid out as at an unknown
      index, its index kept. Identity is content. Its class, layout and what
      it holds are computed when it is made.
      """
  }

||| `!idr.self at m [ts]`, C++ `SelfType`: a member of the group a field is
||| declared in, by position, legal only inside a declaration; a field read
||| of it gives the member's data type. No value has it, so it answers no
||| value facts.
export
selfType : TypeDef 2
selfType = MkTypeDef
  { mnemonic = "self"
  , params =
      [ MkParameter "member" memberPositionKind AlwaysWritten "the member of the group being declared"
      , MkParameter "indices" (WiredValue (WiredArray termWire) termsParam) AlwaysWritten "one term per index, over the constructor's binders" ]
  , syntax = HandSyntax
  , interfaces =
      [ Implements indexedTypeInterface ["getIndexTermRuns", "getPositionalMember"]
      , Implements fieldTypeInterface ["getFieldReach"] ]
  , verifier = AnyParameters
  , bytecode = CheckedBy "readSelf"
  , storage = HandStorage
  , members = []
  , facts = NoValueFacts
  , doc = brief "a member of the group a field is declared in, by position"
  }

||| `#idr.equation<lhs = rhs>`, C++ `EquationAttr`: an erased equality's two
||| index terms, which `idr.index.assume` assumes in its region.
export
equationAttr : AttrDef 2
equationAttr = MkAttrDef
  { mnemonic = "equation"
  , params =
      [ MkParameter "lhs" (WiredValue (WiredArray termWire) termsParam) AlwaysWritten "the left term"
      , MkParameter "rhs" (WiredValue (WiredArray termWire) termsParam) AlwaysWritten "the right term" ]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = CheckedBy "readEquation"
  , storage = HandStorage
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
      [ MkParameter "data" (WiredValue (WiredOne (LeafType "::idr::DataType")) dataParam) AlwaysWritten "the data type, refined to the constructor"
      , MkParameter "cells" (ListOf AttrValue) AlwaysWritten "the cells, each an array of its fields, every one but the last without the spine"
      , MkParameter "spine" CountValue (DefaultsTo "0") "the field a run runs along" ]
  , syntax = HandSyntax
  , typed = Untyped
  , interfaces = [Implements constantAttrInterface ["isBuildableAt", "getStaticForm", "verifyParts", "getClosureHolding"]]
  , verifier = VerifiesParameters
  , bytecode = CheckedBy "readCon"
  , storage = HandStorage
  , members =
      [ MkMember OnClass "::idr::ConAttr" "get" [param "::mlir::MLIRContext *" "context", param "::idr::DataType" "data", param "::mlir::ArrayAttr" "fields"]
      , MkMember OnClass "::idr::ConAttr" "getRun" [param "::mlir::MLIRContext *" "context", param "::idr::DataType" "data", param "unsigned" "spine", param "::llvm::ArrayRef<::mlir::ArrayAttr>" "cells"]
      , MkMember OnClass "::idr::ConAttr" "getNormalized" [param "::llvm::function_ref<::mlir::InFlightDiagnostic()>" "emitError", param "::mlir::MLIRContext *" "context", param "::idr::DataType" "data", param "::llvm::ArrayRef<::mlir::Attribute>" "cells", param "uint64_t" "spine"]
      , MkMember OnObjectConst "::idr::Tag" "getTag" []
      , MkMember OnObjectConst "unsigned" "getRunLength" []
      , MkMember OnObjectConst "::mlir::ArrayAttr" "getCell" [param "unsigned" "cell"]
      , MkMember OnObjectConst "unsigned" "fieldOfCell" [param "unsigned" "cell", param "unsigned" "position"]
      , MkTemplateMember (MkTypeParam "::std::invocable<::mlir::Attribute, unsigned>" "Each" ::: [])
          OnObjectConst "void" "walkFields" [param "Each &&" "each"]
      , MkMember OnObjectConst "::mlir::Attribute" "getField" [param "unsigned" "index"]
      , MkMember OnObjectConst "::mlir::ArrayAttr" "getFields" [] ]
  , doc = brief "a constant constructor value, a run of its cells"
  }
