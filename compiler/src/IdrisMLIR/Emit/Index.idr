-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The program's declarations as the emitters look them up: each family
||| as the member of its group, the `#idr.family` attribute that declares
||| the group whole; and Core's types as the module's. A call holds what it
||| reads of its callee, so no function is looked up. A data type is its family's group and member
||| applied to index terms: its identity is that content, so the module has
||| no table of data types and nothing is looked up by name.
module IdrisMLIR.Emit.Index

import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Spec.Families.Group
import IdrisMLIR.Spec.Families.Layout
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.List
import Data.List1
import Data.Maybe
import Data.SortedMap
import Data.Vect

%default total

||| Whether the values of a type hold references, so that their grade says
||| who frees what they hold: a choice of the type, never a `Bool`.
public export
data Reaches = HoldsReferences | WordsOnly

||| A family as the module declares it: its group's attribute, its place
||| in the group, whether its values hold references, and its group's
||| members by their places, which a field of it refers to as `self`.
public export
record FamilyEntry where
  constructor MkFamilyEntry
  family : Family
  group : MlirAttr
  member : Nat
  reaches : Reaches
  kin : SortedMap FamilyId Nat

public export
record Index where
  constructor MkIndex
  families : SortedMap FamilyId FamilyEntry

||| The families a type is read among: those declared in earlier groups,
||| and the members of the group being declared, each by its place, which
||| a field refers to as `self`.
record Among where
  constructor MkAmong
  declared : SortedMap FamilyId FamilyEntry
  members : SortedMap FamilyId Nat

------------------------------------------------------------------------------
-- What a type holds
------------------------------------------------------------------------------

||| Whether a value of a type holds references. A word does not; a string,
||| a big, a natural (a big when large), a closure, a suspension and an
||| array (its buffer, or the buffer it will be) do; a family's values do
||| when its group says so. A member of the
||| group being declared holds references (`Among.members`): its values
||| are cells of a recursive group.
reachesIn : Among -> Ty -> Reaches
reachesIn a (IntT _) = WordsOnly
reachesIn a CharT = WordsOnly
reachesIn a DoubleT = WordsOnly
reachesIn a WorldT = WordsOnly
reachesIn a (DataT f _) = case lookup f a.members of
  Just _ => HoldsReferences
  Nothing => maybe HoldsReferences (.reaches) (lookup f a.declared)
-- An array's cell is a reference, as the dialect's facts of tensors and
-- memrefs say: used many times and claiming nothing it is the bare type
-- upstream's ops take, and any other grade states who frees it.
reachesIn a _ = HoldsReferences

||| Whether a value of a type holds references, among the program's
||| families.
export
reaches : Index -> Ty -> Reaches
reaches ix = reachesIn (MkAmong ix.families empty)

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

||| A key of `idr.lit.match` as the attribute that holds it (`LitKey`).
export
keyAttr : LitKey -> MlirAttr
keyAttr (IntKey t n) = IntegerAttr (twos (width t) n) (OfWidth (width t))
keyAttr (CharKey c) = IntegerAttr c (OfWidth 32)
keyAttr (StrKey s) = StringAttr s
keyAttr (BigKey n) = Idr (BigAttr n)

||| The axes of an array a function gives: `?` at every one, whatever its
||| size (`returned`).
returnedAxes : List Dim -> List Dim
returnedAxes = map (const Dynamic)

||| A value as a function gives it, whether the function is a definition, a
||| closure's or a suspension's: an array `?` at every axis, whatever its
||| size, which the function's extents keep where it is known. A cast
||| between ranked types is work here (an array's words are its cell and
||| one per dynamic size, and a cast re-packs them), so a call must give
||| the very type its caller returns, or a cast after a tail call would
||| take it out of tail position.
export
returned : Ty -> Ty
returned (TensorT ds e) = TensorT (returnedAxes ds) e
returned t = t

||| A type of the module at a grade: its uses and, for a type that holds
||| references (`Reaches`), who frees what it holds, wrapped around it.
||| The bare type is the grade a type has by itself: a word used many
||| times, the form upstream's ops take, or a value that holds references
||| used many times and freed by its count, claiming nothing.
grade : Uses -> Reaches -> Hold -> MlirType -> MlirType
grade Many WordsOnly _ t = t
grade Once WordsOnly _ t = Idr (GradedType Once Nothing t)
-- A value that holds references, used freely and freed by its count with
-- no claim of its sharing, is the bare type: every such value before
-- counting.
grade Many HoldsReferences (Hold.Counted None) t = t
grade u HoldsReferences h t = Idr (GradedType u (Just h) t)

mutual
  ||| The module's type of a Core type, among the families given. A family
  ||| applied is its group's attribute, its member and its index terms; a
  ||| member of the group being declared is `self`. The world is never
  ||| asked for: its positions are absent from the module.
  typeIn : Among -> Ty -> MlirType
  typeIn a (IntT t) = IntegerType (width t)
  typeIn a CharT = IntegerType 32
  typeIn a DoubleT = F64Type
  typeIn a StrT = Idr StrType
  typeIn a BigT = Idr BigType
  typeIn a (NatT t) = Idr (NatType (nodeIn a t))
  typeIn a WorldT = NoneType
  -- A data type the frontend writes states no binders: a case binds its
  -- constructor's undetermined binders as index variables of its region,
  -- and the C++ states them where it refines a type to one constructor.
  typeIn a (DataT f ts) = case lookup f a.members of
    Just m => Idr (SelfType m (nodesIn a ts))
    Nothing => case lookup f a.declared of
      Just e => Idr (DataType e.group e.member (nodesIn a ts) Nothing [] ByIndices)
      -- A family no group declares is the translation's broken contract;
      -- `Emit.index` declares every family before any type names one.
      Nothing => NoneType
  -- A closure that takes the world takes nothing: IO is ordered by
  -- effects, so an action is a closure of no argument.
  typeIn a (FunT (MkBinder q WorldT) r) = Idr (FnType [] (resultsIn a r))
  typeIn a (FunT (MkBinder q x) r) = Idr (FnType [gradedIn a q made x] (resultsIn a r))
  -- A suspension's value is what its function returns, which the
  -- suspension keeps and gives to every force: used many times.
  typeIn a (LazyT r) = Idr (LazyType (grade Many (reachesIn a r) made (returnedIn a r)))
  typeIn a (TensorT ds e) = tensorIn a ds e
  -- Every memref the frontend writes is an array written while shared, in
  -- the dialect's memory space for it.
  typeIn a (MemRefT o e) = MemRefType (orderedDims o) (typeIn a e) (Just (Idr MutableAttr))

  ||| An array of the dimensions given, of its element's type.
  tensorIn : Among -> List Dim -> Ty -> MlirType
  tensorIn a ds e = RankedTensorType ds (typeIn a e)

  ||| The module's type of a value of a Core type as a function gives it:
  ||| `typeIn` of `returned t`, read off `t`'s own parts, clause for
  ||| clause, so that the walk descends.
  returnedIn : Among -> Ty -> MlirType
  returnedIn a (TensorT ds e) = tensorIn a (returnedAxes ds) e
  returnedIn a t = typeIn a t

  ||| A function's result of a type (`returned`), freed by its count and
  ||| used once: the return hands the caller the one reference it gives,
  ||| and the caller's binding grades it as it is used. Its claim is the
  ||| one its body's returns give it, which idr-unique-results writes;
  ||| `returned` changes no type's reach, so `t`'s is its own.
  resultIn : Among -> Ty -> MlirType
  resultIn a t = grade Once (reachesIn a t) made (returnedIn a t)

  ||| The types a function's result of a type is: none for the world.
  resultsIn : Among -> Ty -> List MlirType
  resultsIn a WorldT = []
  resultsIn a t = [resultIn a t]

  ||| A value's type, at its uses and hold (`grade`).
  gradedIn : Among -> Uses -> Hold -> Ty -> MlirType
  gradedIn a u h t = grade u (reachesIn a t) h (typeIn a t)

  ||| An index term's nodes, in preorder, among the families given: a
  ||| type standing as an index is a literal of its type attribute; a
  ||| constructor of a member of the group being declared names no group,
  ||| one of an earlier group its group's attribute; a constructor of a
  ||| family no group declares is the translation's broken contract, an
  ||| index outside the language here.
  nodesIn : Among -> List ITerm -> List (TermNode MlirType MlirAttr)
  nodesIn a [] = []
  nodesIn a (t :: ts) = nodeIn a t ++ nodesIn a ts

  nodeIn : Among -> ITerm -> List (TermNode MlirType MlirAttr)
  nodeIn a (INat n) = [TermNodeNatural (cast n)]
  nodeIn a (IVar k) = [TermNodeLevel k]
  nodeIn a (ISucc t k) = TermNodeSuccessor k :: nodeIn a t
  -- A sum, its count and how many levels it holds, then each level after
  -- how often it occurs, in ascending order of level.
  nodeIn a (ISum ps k) = TermNodeSum k (length (toList ps)) :: (toList ps >>= \(l, m) => [TermNodeMultiple m, TermNodeLevel l])
  nodeIn a (IType t) = [TermNodeLiteral (TypeAttr (typeIn a t))]
  nodeIn a (ICon f c args) = case lookup f a.members of
    Just m => TermNodeConstructor Nothing m c (length args) :: nodesIn a args
    Nothing => case lookup f a.declared of
      Just e => TermNodeConstructor (Just e.group) e.member c (length args) :: nodesIn a args
      Nothing => [TermNodeOpaque]
  nodeIn a IOpaque = [TermNodeOpaque]

||| The module's type of a Core type, among the program's families.
export
mlirType : Index -> Ty -> MlirType
mlirType ix = typeIn (MkAmong ix.families empty)

||| The module's type of a value of a Core type, used and held as given:
||| its quantity is in the type, where no pass can lose it.
export
gradedType : Index -> Uses -> Hold -> Ty -> MlirType
gradedType ix = gradedIn (MkAmong ix.families empty)

||| The module's types of a function's result of a Core type, among the
||| program's families (`returned`): none for the world.
export
resultTypes : Index -> Ty -> List MlirType
resultTypes ix = resultsIn (MkAmong ix.families empty)

||| A type refined to the constructors given: a family's application known
||| to be one of them, under its grade; the tags are part of the data type,
||| as `DataType::refined` makes it.
refine : MlirType -> List1 Nat -> MlirType
refine (Idr (GradedType u h t)) tags = Idr (GradedType u h (refine t tags))
refine (Idr (DataType g m ts _ bs mark)) tags = Idr (DataType g m ts (Just (DenseI32ArrayAttr (forget tags))) bs mark)
refine t tags = t

||| The module's type of a value of type `t`, used as `u`, held as `h`,
||| known to be the constructors `r` says.
export
valueTypeOf : Index -> Ty -> Uses -> Hold -> Refinement -> MlirType
valueTypeOf ix t u h AnyConstructor = gradedType ix u h t
valueTypeOf ix t u h (OneOf tags) = refine (gradedType ix u h t) tags

||| The module's type of a value: its grade around its type, refined to
||| the constructors it is known to be.
export
valueType : Index -> Val -> MlirType
valueType ix v = valueTypeOf ix v.type v.uses v.hold v.refinement

||| The constructors of a family no case of a match takes, by tag.
export
untaken : Index -> FamilyId -> List Nat -> List Nat
untaken ix f taken = case lookup f ix.families of
  Just e => filter (\t => not (elem t taken)) (take (length e.family.cons) [0 .. length e.family.cons])
  Nothing => []

||| The module's index term of a Core one, among the program's families:
||| its nodes, in preorder.
export
termNodes : Index -> ITerm -> List (TermNode MlirType MlirAttr)
termNodes ix = nodeIn (MkAmong ix.families empty)

||| The `#idr.index_args` of the index terms a call or a lifted function's
||| maker gives: every term's nodes in order, and how many terms they are,
||| counted here from the terms themselves, so the two cannot disagree.
export
indexArgsOf : Index -> List ITerm -> MlirAttr
indexArgsOf ix is = Idr (IndexArgsAttr (concatMap (termNodes ix) is) (length is))

||| The module's sort of a Core sort, among the families given: a member of
||| the group being declared names no group, one of an earlier group its
||| group's attribute.
sortIn : Among -> Sort -> SortOf MlirType MlirAttr
sortIn a SNat = SortOfNatSort
sortIn a SType = SortOfTypeSort
sortIn a SOpaque = SortOfOpaqueSort
sortIn a (SScalar t) = SortOfScalarSort (TypeAttr (typeIn a t))
sortIn a (SFamily f) = case lookup f a.members of
  Just m => SortOfFamilySort Nothing m
  Nothing => case lookup f a.declared of
    Just e => SortOfFamilySort (Just e.group) e.member
    Nothing => SortOfOpaqueSort

||| The module's sort of a Core sort, among the program's families.
export
sortOf : Index -> Sort -> SortOf MlirType MlirAttr
sortOf ix = sortIn (MkAmong ix.families empty)

------------------------------------------------------------------------------
-- Families
------------------------------------------------------------------------------

||| The type a field of type `t` is held at in a cell: an array is its
||| buffer from the frontend on, so no cell holds a tensor; anything else
||| as it is.
fieldTypeIn : Among -> Ty -> MlirType
fieldTypeIn a (TensorT ds e) = MemRefType ds (typeIn a e) Nothing
fieldTypeIn a t = typeIn a t

||| The type a field of type `t` is held at in a cell, among the program's
||| families.
export
fieldType : Index -> Ty -> MlirType
fieldType ix = fieldTypeIn (MkAmong ix.families empty)

||| How far a value's claim on its own cells reaches into a field of a
||| family its library promises so of: an `in_place` family's own cells are
||| the value's; any other family's are not.
promisedReach : Promise -> FieldReach
promisedReach Group.None = Other
promisedReach Group.InPlace = InPlaceFamily

||| How far a value's claim on its own cells reaches into a field of type
||| `t`, which the dialect reads off the type `fieldTypeIn` declares it at
||| (`FieldReach`): a member of the group being declared, `self`, is its own
||| family; a family of an earlier group is as far as its library promises
||| (`promisedReach`); an array is a buffer, held as one or as the buffer of
||| its value, whose storage is the value's; any other field is not reached.
reachIn : Among -> Ty -> FieldReach
reachIn a (TensorT _ _) = HeldBuffer
reachIn a (MemRefT _ _) = HeldBuffer
reachIn a (DataT f _) = case lookup f a.members of
  Just _ => OwnFamily
  Nothing => maybe Other (\e => promisedReach e.family.promise) (lookup f a.declared)
reachIn a _ = Other

||| How far a value of `c`'s family claims into each of its fields, among
||| the families its group was declared among: the reach of each field's
||| declared type. A family no group declares is the translation's broken
||| contract, as in `typeIn`, and its fields reach as no group's do.
export
fieldReaches : Index -> Con k -> Vect k FieldReach
fieldReaches ix c = map (reachIn among . (.type)) c.fields
  where
    among : Among
    among = MkAmong ix.families (maybe empty (.kin) (lookup c.id.family ix.families))

||| The hold of a field's grade: freed by its count with no claim, where
||| its type holds references; none where it holds words.
claimless : Reaches -> Maybe Hold
claimless HoldsReferences = Just made
claimless WordsOnly = Nothing

||| A field of a declaration: its type in its constructor's scope, its
||| quantity the grade it carries (once, or none for many), with no claim
||| of sharing where the type holds references, as every grade of such a
||| type states who frees it; and no field for the world, which is no value
||| of the module.
fieldsIn : Among -> List Binder -> List MlirType
fieldsIn a [] = []
fieldsIn a (MkBinder _ WorldT :: bs) = fieldsIn a bs
fieldsIn a (MkBinder Once t :: bs) = Idr (GradedType Once (claimless (reachesIn a t)) (fieldTypeIn a t)) :: fieldsIn a bs
fieldsIn a (MkBinder Many t :: bs) = fieldTypeIn a t :: fieldsIn a bs

||| A constructor as its family's declaration holds it: its label, its
||| binders' sorts, its equation (one term per index of its family, in its
||| own scope) and its fields.
ctorDecl : Among -> (k ** Con k) -> CtorDecl MlirType MlirAttr
ctorDecl a (_ ** c) =
  MkCtorDecl c.name (map (sortIn a . (.sort)) c.binders) (nodesIn a c.equation) (fieldsIn a (toList c.fields))

||| A family as a member of its group: its label (its key printed, which is
||| part of its identity and never looked up), what its library promises,
||| its declaration's location, its index sorts and its constructors.
memberDecl : Among -> Family -> DataMember MlirType MlirAttr
memberDecl a f =
  MkDataMember (keyText f.key) f.promise (LocAttr (At f.loc)) (map (sortIn a) f.indices) (map (ctorDecl a) f.cons)

||| Whether a group's values hold references: a group whose fields refer
||| to its own members is recursive, so its values are cells; any other
||| holds references when a field does.
groupReaches : Among -> List Family -> Reaches
groupReaches a fs =
  if any (\f => any (\(_ ** c) => any (refersHere . (.type)) (toList c.fields)) f.cons) fs
    then HoldsReferences
    else if any (\f => any (\(_ ** c) => any (holds . (.type)) (toList c.fields)) f.cons) fs
      then HoldsReferences
      else WordsOnly
  where
    refersHere : Ty -> Bool
    refersHere (DataT g _) = isJust (lookup g a.members)
    refersHere _ = False
    holds : Ty -> Bool
    holds t = case reachesIn ({ members := empty } a) t of
      HoldsReferences => True
      WordsOnly => False

||| The families of a program declared, group by group in order, each
||| group one `#idr.family` attribute naming the earlier groups' members
||| by their groups and its own by `self`, numbered by its place in that
||| order: the identity by which the writer encodes it once, however many
||| types name it.
declare : List FamilyGroup -> SortedMap FamilyId FamilyEntry
declare gs = foldl group empty (zip gs [0 .. length gs])
  where
    group : SortedMap FamilyId FamilyEntry -> (FamilyGroup, Nat) -> SortedMap FamilyId FamilyEntry
    group done (g, k) =
      let fs = forget g
          numbered = zip fs [0 .. length fs]
          a = MkAmong done (fromList (map (\(f, m) => (f.id, m)) numbered))
          attr = GroupAttr (MkGroupId k) (map (MemberOfData . memberDecl a) fs)
          r = groupReaches a fs
      in foldl (\m, (f, i) => insert f.id (MkFamilyEntry f attr i r a.members) m) done numbered

||| The index of a program.
export
index : Source -> Index
index src = MkIndex (declare src.groups)
