import TypedSlottedEGraphsPaper.SyntaxSupport
import TypedSlottedEGraphsPaper.Replay

namespace TypedSlottedEGraphsPaper

universe u v w x y z

/-! ## Finite typed contexts and their canonical representatives -/

/-- An explicit countable ordering of the type alphabet.  Injectivity makes
    comparison by `rank` a genuine total order on types. -/
structure OrderedCountableTypeAlphabet (Ty : Type u) where
  rank : Ty → Nat
  rankInjective : Function.Injective rank

namespace OrderedCountableTypeAlphabet

/-- Comparison induced by the declared numerical rank. -/
def le {Ty : Type u} (A : OrderedCountableTypeAlphabet Ty) (a b : Ty) : Prop :=
  A.rank a ≤ A.rank b

/-- Boolean form of the comparison used by executable merge sort. -/
def leBool {Ty : Type u} (A : OrderedCountableTypeAlphabet Ty)
    (a b : Ty) : Bool := decide (A.rank a ≤ A.rank b)

theorem le_trans {Ty : Type u} (A : OrderedCountableTypeAlphabet Ty)
    (a b c : Ty) : A.le a b → A.le b c → A.le a c := by
  simp only [le]
  omega

theorem le_total {Ty : Type u} (A : OrderedCountableTypeAlphabet Ty)
    (a b : Ty) : A.le a b ∨ A.le b a := by
  simp only [le]
  omega

theorem le_antisymm {Ty : Type u} (A : OrderedCountableTypeAlphabet Ty)
    {a b : Ty} (hab : A.le a b) (hba : A.le b a) : a = b := by
  apply A.rankInjective
  simp only [le] at hab hba
  omega

end OrderedCountableTypeAlphabet

/-- The two disjoint infinite typed alphabets used for canonical free and
    binder-local names.  For each type and region, `index : Nat` supplies the
    ordered countable fibre. -/
inductive CanonicalSlotRegion where
  | free
  | bound
  deriving DecidableEq, Repr

structure CanonicalTypedSlot (Ty : Type u) where
  type : Ty
  region : CanonicalSlotRegion
  index : Nat

/-- A finite context is an enumeration of slot types.  Distinct positions are
    distinct slots even when their types agree. -/
structure FiniteTypedContext (Ty : Type u) where
  slotTypes : List Ty

namespace FiniteTypedContext

/-- The core finite typed context represented by the positions of `slotTypes`. -/
def toTypedSlotContext {Ty : Type u} (C : FiniteTypedContext Ty) :
    TypedSlotContext.{u, 0} Ty where
  Slot := Fin C.slotTypes.length
  typeOf := C.slotTypes.get
  cardinalityBound := C.slotTypes.length
  encode := id
  encodeInjective := Function.injective_id

/-- The number of coordinates of a specified type.  Equality is decided by
    the injective rank, avoiding any hidden choice of a type equality test. -/
def typeCardinality {Ty : Type u} (A : OrderedCountableTypeAlphabet Ty)
    (C : FiniteTypedContext Ty) (ty : Ty) : Nat :=
  C.slotTypes.countP (fun candidate => A.rank candidate == A.rank ty)

/-- Canonicalization orders all coordinates by the fixed countable alphabet;
    stability gives a fixed representative for the input enumeration. -/
def canonical {Ty : Type u} (A : OrderedCountableTypeAlphabet Ty)
    (C : FiniteTypedContext Ty) : FiniteTypedContext Ty where
  slotTypes := C.slotTypes.mergeSort A.leBool

/-- The canonical representative is ordered by the declared alphabet. -/
theorem canonical_ordered {Ty : Type u}
    (A : OrderedCountableTypeAlphabet Ty) (C : FiniteTypedContext Ty) :
    (C.canonical A).slotTypes.Pairwise A.le := by
  have sorted := List.pairwise_mergeSort
    (le := A.leBool)
    (fun a b c hab hbc => by
      simp only [OrderedCountableTypeAlphabet.leBool,
        decide_eq_true_eq] at hab hbc ⊢
      exact A.le_trans a b c hab hbc)
    (fun a b => by
      simp only [OrderedCountableTypeAlphabet.leBool, Bool.or_eq_true,
        decide_eq_true_eq]
      exact A.le_total a b)
    C.slotTypes
  change (C.slotTypes.mergeSort A.leBool).Pairwise
    (fun a b => A.rank a ≤ A.rank b)
  simpa only [OrderedCountableTypeAlphabet.leBool, decide_eq_true_eq] using sorted

/-- Canonicalization preserves every type-fibre cardinality. -/
theorem canonical_preserves_typeCardinality {Ty : Type u}
    (A : OrderedCountableTypeAlphabet Ty) (C : FiniteTypedContext Ty)
    (ty : Ty) :
    (C.canonical A).typeCardinality A ty = C.typeCardinality A ty := by
  exact (List.mergeSort_perm C.slotTypes A.leBool).countP_eq _

/-- The canonical core context has exactly as many total slots as the source. -/
theorem canonical_preserves_cardinalityBound {Ty : Type u}
    (A : OrderedCountableTypeAlphabet Ty) (C : FiniteTypedContext Ty) :
    (C.canonical A).toTypedSlotContext.cardinalityBound =
      C.toTypedSlotContext.cardinalityBound := by
  exact List.length_mergeSort C.slotTypes

/-- Position `i` in a canonical context denotes the `i`th sorted free slot;
    this exposes the connection to the reserved canonical free alphabet. -/
def canonicalSlotName {Ty : Type u} (A : OrderedCountableTypeAlphabet Ty)
    (C : FiniteTypedContext Ty)
    (slot : (C.canonical A).toTypedSlotContext.Slot) : CanonicalTypedSlot Ty where
  type := (C.canonical A).slotTypes.get slot
  region := .free
  index := ((C.canonical A).slotTypes.take slot.val).countP
    (fun candidate =>
      A.rank candidate == A.rank ((C.canonical A).slotTypes.get slot))

@[simp] theorem canonicalSlotName_type {Ty : Type u}
    (A : OrderedCountableTypeAlphabet Ty) (C : FiniteTypedContext Ty)
    (slot : (C.canonical A).toTypedSlotContext.Slot) :
    (C.canonicalSlotName A slot).type =
      (C.canonical A).toTypedSlotContext.typeOf slot := rfl

@[simp] theorem canonicalSlotName_region {Ty : Type u}
    (A : OrderedCountableTypeAlphabet Ty) (C : FiniteTypedContext Ty)
    (slot : (C.canonical A).toTypedSlotContext.Slot) :
    (C.canonicalSlotName A slot).region = CanonicalSlotRegion.free := rfl

/-- The name assigned to a canonical slot is one of the first `k` free names
    in its own type fibre, where `k` is that fibre's cardinality. -/
theorem canonicalSlotName_index_lt_typeCardinality {Ty : Type u}
    (A : OrderedCountableTypeAlphabet Ty) (C : FiniteTypedContext Ty)
    (slot : (C.canonical A).toTypedSlotContext.Slot) :
    (C.canonicalSlotName A slot).index <
      (C.canonical A).typeCardinality A
        ((C.canonicalSlotName A slot).type) := by
  let types := (C.canonical A).slotTypes
  have slotInTypes : slot.val < types.length := by
    exact slot.isLt
  let predicate := fun candidate : Ty =>
    A.rank candidate == A.rank types[slot.val]
  change (types.take slot.val).countP predicate < types.countP predicate
  have predicateAtSlot : predicate types[slot.val] = true := by
    simp only [predicate, beq_self_eq_true]
  have prefixCount :
      (types.take (slot.val + 1)).countP predicate =
        (types.take slot.val).countP predicate + 1 := by
    rw [List.take_succ_eq_append_getElem slotInTypes,
      List.countP_append, List.countP_singleton, predicateAtSlot]
    simp only [if_true]
  have bounded := (List.take_sublist (slot.val + 1) types).countP_le
    (p := predicate)
  omega

/-- Complete executable evidence for the paper's F02 environment: the sorted
    canonical context, all preserved fibre counts, and a typed free name from
    the initial segment of each type fibre. -/
structure VerifiedCanonicalContext {Ty : Type u}
    (A : OrderedCountableTypeAlphabet Ty) (source : FiniteTypedContext Ty) where
  canonical : FiniteTypedContext Ty
  canonicalEquation : canonical = source.canonical A
  ordered : canonical.slotTypes.Pairwise A.le
  preservesTypeCardinality : ∀ ty,
    canonical.typeCardinality A ty = source.typeCardinality A ty
  freeName : canonical.toTypedSlotContext.Slot → CanonicalTypedSlot Ty
  freeNameType : ∀ slot,
    (freeName slot).type = canonical.toTypedSlotContext.typeOf slot
  freeNameRegion : ∀ slot, (freeName slot).region = CanonicalSlotRegion.free
  freeNameWithinTypeFibre : ∀ slot,
    (freeName slot).index < canonical.typeCardinality A (freeName slot).type

/-- F02: construct the complete canonical-context environment from finite
    context data and the fixed ordered countable alphabet. -/
def f02CanonicalContextEncoding {Ty : Type u}
    (A : OrderedCountableTypeAlphabet Ty) (source : FiniteTypedContext Ty) :
    VerifiedCanonicalContext A source where
  canonical := source.canonical A
  canonicalEquation := rfl
  ordered := source.canonical_ordered A
  preservesTypeCardinality := source.canonical_preserves_typeCardinality A
  freeName := source.canonicalSlotName A
  freeNameType := source.canonicalSlotName_type A
  freeNameRegion := source.canonicalSlotName_region A
  freeNameWithinTypeFibre :=
    source.canonicalSlotName_index_lt_typeCardinality A

end FiniteTypedContext

/-! ## A finite typed parent forest and total leader finding -/

/-- A typed parent link preserves the class output and embeds the parent
    interface into the child's interface. -/
structure TypedForestParentLink {Ty : Type u} {ClassId : Type v}
    (classOutput : ClassId → Ty)
    (interface : ClassId → TypedSlotContext.{u, w} Ty)
    (child : ClassId) where
  parent : ClassId
  outputPreserved : classOutput parent = classOutput child
  embedding : TypedSlotEmbedding (interface parent) (interface child)

/-- A finite parent forest.  `depth` is executable termination data, while
    `parentDecreases` excludes every parent cycle. -/
structure FiniteTypedParentForest (Ty : Type u) (ClassId : Type v)
    (classOutput : ClassId → Ty)
    (interface : ClassId → TypedSlotContext.{u, w} Ty) where
  classCardinalityBound : Nat
  classEncode : ClassId → Fin classCardinalityBound
  classEncodeInjective : Function.Injective classEncode
  parent : (child : ClassId) →
    Option (TypedForestParentLink classOutput interface child)
  depth : ClassId → Nat
  parentDecreases : ∀ (child : ClassId)
    (edge : TypedForestParentLink classOutput interface child),
    parent child = some edge → depth edge.parent < depth child

namespace FiniteTypedParentForest

variable {Ty : Type u} {ClassId : Type v}
  {classOutput : ClassId → Ty}
  {interface : ClassId → TypedSlotContext.{u, w} Ty}
  (F : FiniteTypedParentForest Ty ClassId classOutput interface)

/-- A checked route through the stored forest to a root. -/
inductive ParentPath : ClassId → ClassId → Type (max u v w) where
  | root (leader : ClassId) (isRoot : F.parent leader = none) :
      ParentPath leader leader
  | step {child : ClassId}
      (edge : TypedForestParentLink classOutput interface child)
      (isParent : F.parent child = some edge)
      {leader : ClassId} (rest : ParentPath edge.parent leader) :
      ParentPath child leader

namespace ParentPath

/-- Composition of every typed parent embedding on a checked path. -/
def embedding {F : FiniteTypedParentForest Ty ClassId classOutput interface}
    {child leader : ClassId} (path : F.ParentPath child leader) :
    TypedSlotEmbedding (interface leader) (interface child) :=
  match path with
  | .root leader _ => TypedSlotEmbedding.id (interface leader)
  | .step edge _ rest =>
      TypedSlotEmbedding.comp edge.embedding rest.embedding

theorem leader_isRoot
    {F : FiniteTypedParentForest Ty ClassId classOutput interface}
    {child leader : ClassId} (path : F.ParentPath child leader) :
    F.parent leader = none := by
  induction path with
  | root leader isRoot => exact isRoot
  | step edge isParent rest ih => exact ih

theorem output_preserved
    {F : FiniteTypedParentForest Ty ClassId classOutput interface}
    {child leader : ClassId} (path : F.ParentPath child leader) :
    classOutput leader = classOutput child := by
  induction path with
  | root leader isRoot => rfl
  | step edge isParent rest ih => exact ih.trans edge.outputPreserved

/-- A checked path starting at a root has a surjective composite embedding;
    a nontrivial first step would contradict the root equation. -/
theorem embedding_surjective_of_start_root
    {F : FiniteTypedParentForest Ty ClassId classOutput interface}
    {child leader : ClassId} (path : F.ParentPath child leader)
    (startIsRoot : F.parent child = none) :
    Function.Surjective path.embedding.toFun := by
  cases path with
  | root leader isRoot =>
      intro slot
      exact ⟨slot, rfl⟩
  | step edge isParent rest =>
      rw [startIsRoot] at isParent
      contradiction

end ParentPath

/-- The result of total forest lookup: a root and the complete typed path. -/
structure FindResult (child : ClassId) where
  leader : ClassId
  path : F.ParentPath child leader

/-- Total leader finding, justified by the strictly decreasing stored depth. -/
def find (child : ClassId) : F.FindResult child :=
  match hparent : F.parent child with
  | none => ⟨child, .root child hparent⟩
  | some edge =>
      let found := find edge.parent
      ⟨found.leader, .step edge hparent found.path⟩
termination_by F.depth child
decreasing_by
  exact F.parentDecreases child edge hparent

/-- The embedding returned by `find` is the composite of its parent path. -/
def FindResult.embedding {child : ClassId} (found : F.FindResult child) :
    TypedSlotEmbedding (interface found.leader) (interface child) :=
  found.path.embedding

theorem find_isLeader (child : ClassId) :
    F.parent (F.find child).leader = none :=
  (F.find child).path.leader_isRoot

theorem find_preserves_output (child : ClassId) :
    classOutput (F.find child).leader = classOutput child :=
  (F.find child).path.output_preserved

/-- Image support cannot grow when a caller embedding is precomposed with a
    checked parent path. -/
theorem parentPath_support_contracts {child leader : ClassId}
    (path : F.ParentPath child leader)
    {caller : TypedSlotContext.{u, w} Ty}
    (embedding : TypedSlotEmbedding (interface child) caller) {slot : caller.Slot} :
    (∃ leaderSlot,
      (TypedSlotEmbedding.comp embedding path.embedding).toFun leaderSlot = slot) →
    ∃ childSlot, embedding.toFun childSlot = slot := by
  exact TypedSlotEmbedding.range_comp_subset embedding path.embedding

/-- Leader finding contracts invocation support in the same caller context. -/
theorem find_support_contracts (child : ClassId)
    {caller : TypedSlotContext.{u, w} Ty}
    (embedding : TypedSlotEmbedding (interface child) caller) {slot : caller.Slot} :
    (∃ leaderSlot,
      (TypedSlotEmbedding.comp embedding (F.find child).embedding).toFun
        leaderSlot = slot) →
    ∃ childSlot, embedding.toFun childSlot = slot := by
  exact F.parentPath_support_contracts (F.find child).path embedding

end FiniteTypedParentForest

/-! ## Stored shapes, exact collision buckets, and class symmetries -/

/-- The non-key witness stored with one owned shape: the owner's interface is
    included in an explicit ambient support, while the shape's exact slots are
    renamed bijectively onto that same ambient support. -/
structure TypedStoredShapeRecord {Ty : Type u} {ClassId : Type v}
    {Shape : Type x}
    (interface : ClassId → TypedSlotContext.{u, w} Ty)
    (shapeContext : Shape → TypedSlotContext.{u, w} Ty)
    (owner : ClassId) (shape : Shape) where
  ambient : TypedSlotContext.{u, w} Ty
  ownerInAmbient : TypedSlotEmbedding (interface owner) ambient
  shapeToAmbient : TypedSlotRenaming (shapeContext shape) ambient

/-- A quiescent typed e-graph augments the finite forest with finitely stored
    typed shapes, an exact collision index, and certified class symmetry
    groups.  These are representation invariants, not conclusions of the
    support or transport theorems below. -/
structure QuiescentFiniteTypedEGraph
    (Ty : Type u) (ClassId : Type v) (Shape : Type x)
    (classOutput : ClassId → Ty) (shapeOutput : Shape → Ty)
    (interface : ClassId → TypedSlotContext.{u, w} Ty) where
  forest : FiniteTypedParentForest Ty ClassId classOutput interface
  storedShape : ClassId → Shape → Prop
  shapeContext : Shape → TypedSlotContext.{u, w} Ty
  storedShapeTyped : ∀ {owner shape},
    storedShape owner shape → shapeOutput shape = classOutput owner
  storedShapeRecord : ∀ {owner shape}, storedShape owner shape →
    TypedStoredShapeRecord interface shapeContext owner shape
  storedShapeCardinalityBound : ClassId → Nat
  storedShapeEncode : ∀ owner,
    {shape : Shape // storedShape owner shape} →
      Fin (storedShapeCardinalityBound owner)
  storedShapeEncodeInjective : ∀ owner,
    Function.Injective (storedShapeEncode owner)
  collisionOwner : Shape → ClassId → Prop
  collisionExact : ∀ shape owner,
    collisionOwner shape owner ↔
      forest.parent owner = none ∧ storedShape owner shape
  classSymmetry : (owner : ClassId) →
    TypedSlotRenaming (interface owner) (interface owner) → Prop
  classSymmetryId : ∀ owner,
    classSymmetry owner (TypedSlotRenaming.id (interface owner))
  classSymmetryInverse : ∀ {owner symmetry},
    classSymmetry owner symmetry → classSymmetry owner symmetry.symm
  classSymmetryComposition : ∀ {owner left right},
    classSymmetry owner left → classSymmetry owner right →
      classSymmetry owner (TypedSlotRenaming.comp left right)

namespace QuiescentFiniteTypedEGraph

variable {Ty : Type u} {ClassId : Type v} {Shape : Type x}
  {classOutput : ClassId → Ty} {shapeOutput : Shape → Ty}
  {interface : ClassId → TypedSlotContext.{u, w} Ty}
  (G : QuiescentFiniteTypedEGraph Ty ClassId Shape classOutput
    shapeOutput interface)

/-- A collision bucket is defined exactly when a root owns the shape. -/
theorem collision_defined_iff_leader_owns (shape : Shape) :
    (∃ owner, G.collisionOwner shape owner) ↔
      ∃ owner, G.forest.parent owner = none ∧ G.storedShape owner shape := by
  constructor
  · rintro ⟨owner, collision⟩
    exact ⟨owner, (G.collisionExact shape owner).mp collision⟩
  · rintro ⟨owner, root, owns⟩
    exact ⟨owner, (G.collisionExact shape owner).mpr ⟨root, owns⟩⟩

/-- Named whole-state wrapper for F10.  Its state contains the finite class
    encoding, decreasing parent forest, stored-shape finiteness witness, exact
    quiescent collision index, ambient shape witnesses, and all class symmetry
    groups. -/
structure F10FiniteQuiescentGraphEnvironment where
  state : QuiescentFiniteTypedEGraph Ty ClassId Shape classOutput
    shapeOutput interface

/-- F10: package a checked quiescent graph as the paper's graph environment. -/
def f10FiniteQuiescentGraphEncoding :
    F10FiniteQuiescentGraphEnvironment
      (classOutput := classOutput) (shapeOutput := shapeOutput)
      (interface := interface) where
  state := G

namespace F10FiniteQuiescentGraphEnvironment

def find
    (environment : F10FiniteQuiescentGraphEnvironment
      (classOutput := classOutput) (shapeOutput := shapeOutput)
      (interface := interface))
    (classId : ClassId) : environment.state.forest.FindResult classId :=
  environment.state.forest.find classId

theorem find_isLeader
    (environment : F10FiniteQuiescentGraphEnvironment
      (classOutput := classOutput) (shapeOutput := shapeOutput)
      (interface := interface))
    (classId : ClassId) :
    environment.state.forest.parent (environment.find classId).leader = none :=
  environment.state.forest.find_isLeader classId

theorem collisionIndexExact
    (environment : F10FiniteQuiescentGraphEnvironment
      (classOutput := classOutput) (shapeOutput := shapeOutput)
      (interface := interface))
    (shape : Shape) (owner : ClassId) :
    environment.state.collisionOwner shape owner ↔
      environment.state.forest.parent owner = none ∧
        environment.state.storedShape owner shape :=
  environment.state.collisionExact shape owner

end F10FiniteQuiescentGraphEnvironment

/-- An invocation is a class interface embedded in a finite caller context. -/
structure GraphInvocation
    (graph : QuiescentFiniteTypedEGraph Ty ClassId Shape classOutput
      shapeOutput interface)
    (caller : TypedSlotContext.{u, w} Ty) where
  classId : ClassId
  embedding : TypedSlotEmbedding (interface classId) caller

namespace GraphInvocation

/-- Transport along any typed embedding; renaming is the bijective case. -/
abbrev transport {caller target : TypedSlotContext.{u, w} Ty}
    (outer : TypedSlotEmbedding caller target)
    (invocation : G.GraphInvocation caller) : G.GraphInvocation target where
  classId := invocation.classId
  embedding := TypedSlotEmbedding.comp outer invocation.embedding

/-- Typed transport of an invocation to a renamed caller context. -/
abbrev rename {caller target : TypedSlotContext.{u, w} Ty}
    (transport : TypedSlotRenaming caller target)
    (invocation : G.GraphInvocation caller) : G.GraphInvocation target :=
  GraphInvocation.transport G transport.toTypedSlotEmbedding invocation

/-- The post-find support of an invocation is the image of the composed
    leader embedding in its caller. -/
def LeaderSupports {caller : TypedSlotContext.{u, w} Ty}
    (invocation : G.GraphInvocation caller) (slot : caller.Slot) : Prop :=
  let found := G.forest.find invocation.classId
  ∃ leaderSlot,
    (TypedSlotEmbedding.comp invocation.embedding found.embedding).toFun
      leaderSlot = slot

end GraphInvocation

/-- Graph-relative alignment of invocation leaves.  Both checked forest paths
    end at one leader, and their caller maps differ by an admitted symmetry of
    that leader. -/
def GraphInvocationAlignedBy
    {leftCaller rightCaller : TypedSlotContext.{u, w} Ty}
    (alignment : TypedSlotRenaming leftCaller rightCaller)
    (left : G.GraphInvocation leftCaller)
    (right : G.GraphInvocation rightCaller) : Prop :=
  ∃ (leader : ClassId)
    (leftPath : G.forest.ParentPath left.classId leader)
    (rightPath : G.forest.ParentPath right.classId leader)
    (symmetry : TypedSlotRenaming (interface leader) (interface leader)),
    G.classSymmetry leader symmetry ∧
      TypedSlotEmbedding.comp alignment.toTypedSlotEmbedding
        (TypedSlotEmbedding.comp left.embedding leftPath.embedding) =
      TypedSlotEmbedding.comp
        (TypedSlotEmbedding.comp right.embedding rightPath.embedding)
        symmetry.toTypedSlotEmbedding

/-- The conjugated alignment induced by independent caller transports. -/
def transportedAlignment
    {leftCaller rightCaller leftTarget rightTarget :
      TypedSlotContext.{u, w} Ty}
    (alignment : TypedSlotRenaming leftCaller rightCaller)
    (leftTransport : TypedSlotRenaming leftCaller leftTarget)
    (rightTransport : TypedSlotRenaming rightCaller rightTarget) :
    TypedSlotRenaming leftTarget rightTarget :=
  TypedSlotRenaming.comp rightTransport
    (TypedSlotRenaming.comp alignment leftTransport.symm)

/-- Invocation-level graph-relative structure is stable under independent
    typed renaming of both caller contexts. -/
theorem graphInvocationAlignment_transport
    {leftCaller rightCaller leftTarget rightTarget :
      TypedSlotContext.{u, w} Ty}
    (alignment : TypedSlotRenaming leftCaller rightCaller)
    (leftTransport : TypedSlotRenaming leftCaller leftTarget)
    (rightTransport : TypedSlotRenaming rightCaller rightTarget)
    (left : G.GraphInvocation leftCaller)
    (right : G.GraphInvocation rightCaller)
    (related : G.GraphInvocationAlignedBy alignment left right) :
    G.GraphInvocationAlignedBy
      (transportedAlignment alignment leftTransport rightTransport)
      (GraphInvocation.rename G leftTransport left)
      (GraphInvocation.rename G rightTransport right) := by
  rcases related with
    ⟨leader, leftPath, rightPath, symmetry, symmetryAllowed, equation⟩
  refine ⟨leader, leftPath, rightPath, symmetry, symmetryAllowed, ?_⟩
  apply TypedSlotEmbedding.ext
  intro slot
  have cancelLeft := congrArg
    (fun embedding => embedding.toFun
      ((TypedSlotEmbedding.comp left.embedding leftPath.embedding).toFun slot))
    leftTransport.leftInverse
  have alignedPoint := congrArg (fun embedding => embedding.toFun slot) equation
  simp only [TypedSlotEmbedding.comp_apply, TypedSlotEmbedding.id_apply] at cancelLeft alignedPoint
  simp only [transportedAlignment, GraphInvocation.rename,
    TypedSlotRenaming.comp, TypedSlotRenaming.symm,
    TypedSlotEmbedding.comp_apply]
  rw [cancelLeft, alignedPoint]

/-- A leader invocation has no remaining parent link. -/
structure LeaderInvocation
    (caller : TypedSlotContext.{u, w} Ty) (leader : ClassId) where
  isLeader : G.forest.parent leader = none
  embedding : TypedSlotEmbedding (interface leader) caller

namespace LeaderInvocation

def Supports {caller : TypedSlotContext.{u, w} Ty} {leader : ClassId}
    (invocation : G.LeaderInvocation caller leader) (slot : caller.Slot) : Prop :=
  ∃ leaderSlot, invocation.embedding.toFun leaderSlot = slot

end LeaderInvocation

/-- Alignment specialized to already leader-normalized invocations. -/
def LeaderInvocationAlignedBy
    {leftCaller rightCaller : TypedSlotContext.{u, w} Ty}
    {leader : ClassId}
    (alignment : TypedSlotRenaming leftCaller rightCaller)
    (left : G.LeaderInvocation leftCaller leader)
    (right : G.LeaderInvocation rightCaller leader) : Prop :=
  ∃ symmetry : TypedSlotRenaming (interface leader) (interface leader),
    G.classSymmetry leader symmetry ∧
      TypedSlotEmbedding.comp alignment.toTypedSlotEmbedding left.embedding =
        TypedSlotEmbedding.comp right.embedding
          symmetry.toTypedSlotEmbedding

/-- Under identity caller alignment, admitted leader symmetry preserves the
    exact image support of a leader-normalized invocation. -/
theorem identityAlignedLeaderSupport
    {caller : TypedSlotContext.{u, w} Ty} {leader : ClassId}
    (left right : G.LeaderInvocation caller leader)
    (related : G.LeaderInvocationAlignedBy
      (TypedSlotRenaming.id caller) left right)
    (slot : caller.Slot) :
    LeaderInvocation.Supports G left slot ↔
      LeaderInvocation.Supports G right slot := by
  rcases related with ⟨symmetry, symmetryAllowed, equation⟩
  have maps : left.embedding = TypedSlotEmbedding.comp right.embedding
      symmetry.toTypedSlotEmbedding := by
    exact (TypedSlotEmbedding.id_comp left.embedding).symm.trans equation
  constructor
  · rintro ⟨leaderSlot, supported⟩
    refine ⟨symmetry.toTypedSlotEmbedding.toFun leaderSlot, ?_⟩
    rw [← supported, maps]
    rfl
  · rintro ⟨leaderSlot, supported⟩
    refine ⟨symmetry.inverse.toFun leaderSlot, ?_⟩
    rw [maps]
    simp only [TypedSlotEmbedding.comp_apply]
    have rightInversePoint := congrArg (fun embedding => embedding.toFun leaderSlot)
      symmetry.rightInverse
    simp only [TypedSlotEmbedding.comp_apply, TypedSlotEmbedding.id_apply] at rightInversePoint
    rw [rightInversePoint, supported]

/-- The direct image form needed at leader-normalized leaves.  The root
    hypotheses rule out a proper first parent edge, so both checked paths in
    the graph-relative alignment are reflexive at the common leader. -/
theorem identityAlignedRootInvocationDirectSupport
    {caller : TypedSlotContext.{u, w} Ty}
    (left right : G.GraphInvocation caller)
    (leftRoot : G.forest.parent left.classId = none)
    (rightRoot : G.forest.parent right.classId = none)
    (related : G.GraphInvocationAlignedBy
      (TypedSlotRenaming.id caller) left right)
    (slot : caller.Slot) :
    (∃ classSlot, left.embedding.toFun classSlot = slot) ↔
      ∃ classSlot, right.embedding.toFun classSlot = slot := by
  rcases related with
    ⟨leader, leftPath, rightPath, symmetry, symmetryAllowed, equation⟩
  have leftSurjective := leftPath.embedding_surjective_of_start_root leftRoot
  have rightSurjective := rightPath.embedding_surjective_of_start_root rightRoot
  have alignedPoint : ∀ leaderSlot,
      left.embedding.toFun (leftPath.embedding.toFun leaderSlot) =
        right.embedding.toFun
          (rightPath.embedding.toFun
            (symmetry.toTypedSlotEmbedding.toFun leaderSlot)) := by
    intro leaderSlot
    have point := congrArg (fun embedding => embedding.toFun leaderSlot) equation
    simpa only [TypedSlotEmbedding.comp_apply, TypedSlotRenaming.id,
      TypedSlotEmbedding.id_apply] using point
  constructor
  · rintro ⟨classSlot, supported⟩
    rcases leftSurjective classSlot with ⟨leaderSlot, reaches⟩
    refine ⟨rightPath.embedding.toFun
      (symmetry.toTypedSlotEmbedding.toFun leaderSlot), ?_⟩
    calc
      right.embedding.toFun
          (rightPath.embedding.toFun
            (symmetry.toTypedSlotEmbedding.toFun leaderSlot)) =
          left.embedding.toFun (leftPath.embedding.toFun leaderSlot) :=
        (alignedPoint leaderSlot).symm
      _ = left.embedding.toFun classSlot := congrArg left.embedding.toFun reaches
      _ = slot := supported
  · rintro ⟨classSlot, supported⟩
    rcases rightSurjective classSlot with ⟨leaderSlot, reaches⟩
    refine ⟨leftPath.embedding.toFun (symmetry.inverse.toFun leaderSlot), ?_⟩
    have inversePoint := congrArg (fun embedding => embedding.toFun leaderSlot)
      symmetry.rightInverse
    simp only [TypedSlotEmbedding.comp_apply,
      TypedSlotEmbedding.id_apply] at inversePoint
    calc
      left.embedding.toFun
          (leftPath.embedding.toFun (symmetry.inverse.toFun leaderSlot)) =
          right.embedding.toFun
            (rightPath.embedding.toFun
              (symmetry.toTypedSlotEmbedding.toFun
                (symmetry.inverse.toFun leaderSlot))) :=
        alignedPoint (symmetry.inverse.toFun leaderSlot)
      _ = right.embedding.toFun (rightPath.embedding.toFun leaderSlot) := by
        rw [inversePoint]
      _ = right.embedding.toFun classSlot := congrArg right.embedding.toFun reaches
      _ = slot := supported

/-! ## Recursive graph-relative ports and nodes -/

/- A faithful intrinsically typed structural carrier for the F14/F15 lift.
    The separate length-indexed forest avoids an unchecked host-language list
    invariant while retaining sequences, bags, sets, binders, and nodes. -/
mutual
  inductive GraphStructuredValue
      (graph : QuiescentFiniteTypedEGraph Ty ClassId Shape classOutput
        shapeOutput interface)
      (Block : Type y) (blockTypes : Block → List Ty)
      (Operator : Ty → Type z) :
      TypedSlotContext.{u, w} Ty → List Ty → Ty → Type _ where
    | free {context : TypedSlotContext.{u, w} Ty} {bound : List Ty}
        {output : Ty} (slot : context.Slot)
        (wellTyped : context.typeOf slot = output) :
        GraphStructuredValue graph Block blockTypes Operator context bound output
    | invocation {context : TypedSlotContext.{u, w} Ty} {bound : List Ty}
        {output : Ty} (value : graph.GraphInvocation context)
        (wellTyped : classOutput value.classId = output) :
        GraphStructuredValue graph Block blockTypes Operator context bound output
    | sequence {context : TypedSlotContext.{u, w} Ty} {bound : List Ty}
        {output : Ty} {size : Nat}
        (children : GraphStructuredForest graph Block blockTypes Operator
          context bound output size) :
        GraphStructuredValue graph Block blockTypes Operator context bound output
    | bag {context : TypedSlotContext.{u, w} Ty} {bound : List Ty}
        {output : Ty} {size : Nat}
        (occurrences : GraphStructuredForest graph Block blockTypes Operator
          context bound output size) :
        GraphStructuredValue graph Block blockTypes Operator context bound output
    | set {context : TypedSlotContext.{u, w} Ty} {bound : List Ty}
        {output : Ty} {size : Nat}
        (representatives : GraphStructuredForest graph Block blockTypes Operator
          context bound output size) :
        GraphStructuredValue graph Block blockTypes Operator context bound output
    | binder {context : TypedSlotContext.{u, w} Ty} {bound : List Ty}
        {output : Ty} (boundType : Ty)
        (body : GraphStructuredValue graph Block blockTypes Operator context
          (boundType :: bound) output) :
        GraphStructuredValue graph Block blockTypes Operator context bound output
    | binderBlock {context : TypedSlotContext.{u, w} Ty} {bound : List Ty}
        {output : Ty} (descriptor : Block)
        (body : GraphStructuredValue graph Block blockTypes Operator context
          (blockTypes descriptor ++ bound) output) :
        GraphStructuredValue graph Block blockTypes Operator context bound output
    | node {context : TypedSlotContext.{u, w} Ty} {bound : List Ty}
        {output : Ty} {size : Nat} (operator : Operator output)
        (children : GraphStructuredForest graph Block blockTypes Operator
          context bound output size) :
        GraphStructuredValue graph Block blockTypes Operator context bound output

  inductive GraphStructuredForest
      (graph : QuiescentFiniteTypedEGraph Ty ClassId Shape classOutput
        shapeOutput interface)
      (Block : Type y) (blockTypes : Block → List Ty)
      (Operator : Ty → Type z) :
      TypedSlotContext.{u, w} Ty → List Ty → Ty → Nat → Type _ where
    | nil {context : TypedSlotContext.{u, w} Ty} {bound : List Ty}
        {output : Ty} :
        GraphStructuredForest graph Block blockTypes Operator
          context bound output 0
    | cons {context : TypedSlotContext.{u, w} Ty} {bound : List Ty}
        {output : Ty} {size : Nat}
        (head : GraphStructuredValue graph Block blockTypes Operator
          context bound output)
        (tail : GraphStructuredForest graph Block blockTypes Operator
          context bound output size) :
        GraphStructuredForest graph Block blockTypes Operator
          context bound output (size + 1)
end

namespace GraphStructuredValue

mutual
  /-- Outer-context action; bound indices are unchanged. -/
  def act {Block : Type y} {blockTypes : Block → List Ty}
      {Operator : Ty → Type z}
      {source target : TypedSlotContext.{u, w} Ty}
      (outer : TypedSlotEmbedding source target) {bound : List Ty} {output : Ty} :
      G.GraphStructuredValue Block blockTypes Operator source bound output →
        G.GraphStructuredValue Block blockTypes Operator target bound output
    | .free slot wellTyped =>
        .free (outer.toFun slot) ((outer.preservesType slot).trans wellTyped)
    | .invocation value wellTyped =>
        .invocation (GraphInvocation.transport G outer value) wellTyped
    | .sequence children => .sequence (GraphStructuredForest.act outer children)
    | .bag occurrences => .bag (GraphStructuredForest.act outer occurrences)
    | .set representatives => .set (GraphStructuredForest.act outer representatives)
    | .binder boundType body => .binder boundType (act outer body)
    | .binderBlock descriptor body =>
        .binderBlock descriptor (act outer body)
    | .node operator children =>
        .node operator (GraphStructuredForest.act outer children)

  /-- Componentwise outer-context action on a structural forest. -/
  def GraphStructuredForest.act {Block : Type y}
      {blockTypes : Block → List Ty} {Operator : Ty → Type z}
      {source target : TypedSlotContext.{u, w} Ty}
      (outer : TypedSlotEmbedding source target) {bound : List Ty} {output : Ty}
      {size : Nat} :
      G.GraphStructuredForest Block blockTypes Operator source bound output size →
        G.GraphStructuredForest Block blockTypes Operator target bound output size
    | .nil => .nil
    | .cons head tail => .cons (act outer head) (GraphStructuredForest.act outer tail)
end

mutual
  /-- Exact free support of a structural value. -/
  def Supports {Block : Type y} {blockTypes : Block → List Ty}
      {Operator : Ty → Type z}
      {context : TypedSlotContext.{u, w} Ty} {bound : List Ty} {output : Ty} :
      G.GraphStructuredValue Block blockTypes Operator context bound output →
        context.Slot → Prop
    | .free ownSlot _, candidate => ownSlot = candidate
    | .invocation value _, candidate =>
        ∃ classSlot, value.embedding.toFun classSlot = candidate
    | .sequence children, candidate => GraphStructuredForest.Supports children candidate
    | .bag occurrences, candidate => GraphStructuredForest.Supports occurrences candidate
    | .set representatives, candidate =>
        GraphStructuredForest.Supports representatives candidate
    | .binder _ body, candidate => Supports body candidate
    | .binderBlock _ body, candidate => Supports body candidate
    | .node _ children, candidate => GraphStructuredForest.Supports children candidate

  def GraphStructuredForest.Supports {Block : Type y}
      {blockTypes : Block → List Ty} {Operator : Ty → Type z}
      {context : TypedSlotContext.{u, w} Ty} {bound : List Ty} {output : Ty}
      {size : Nat} :
      G.GraphStructuredForest Block blockTypes Operator context bound output size →
        context.Slot → Prop
    | .nil, _ => False
    | .cons head tail, candidate =>
        Supports head candidate ∨ GraphStructuredForest.Supports tail candidate
end

mutual
  /-- Every invocation leaf is already a forest root. -/
  def LeaderNormalized {Block : Type y} {blockTypes : Block → List Ty}
      {Operator : Ty → Type z}
      {context : TypedSlotContext.{u, w} Ty} {bound : List Ty} {output : Ty} :
      G.GraphStructuredValue Block blockTypes Operator context bound output → Prop
    | .free _ _ => True
    | .invocation value _ => G.forest.parent value.classId = none
    | .sequence children => GraphStructuredForest.LeaderNormalized children
    | .bag occurrences => GraphStructuredForest.LeaderNormalized occurrences
    | .set representatives =>
        GraphStructuredForest.LeaderNormalized representatives
    | .binder _ body => LeaderNormalized body
    | .binderBlock _ body => LeaderNormalized body
    | .node _ children => GraphStructuredForest.LeaderNormalized children

  def GraphStructuredForest.LeaderNormalized {Block : Type y}
      {blockTypes : Block → List Ty} {Operator : Ty → Type z}
      {context : TypedSlotContext.{u, w} Ty} {bound : List Ty} {output : Ty}
      {size : Nat} :
      G.GraphStructuredForest Block blockTypes Operator context bound output size → Prop
    | .nil => True
    | .cons head tail =>
        LeaderNormalized head ∧ GraphStructuredForest.LeaderNormalized tail
end

end GraphStructuredValue

namespace GraphStructuredValue.GraphStructuredForest

/-- Position lookup in a length-indexed structural forest. -/
def get {Block : Type y} {blockTypes : Block → List Ty}
    {Operator : Ty → Type z}
    {context : TypedSlotContext.{u, w} Ty} {bound : List Ty} {output : Ty} :
    {size : Nat} →
    G.GraphStructuredForest Block blockTypes Operator context bound output size →
      Fin size → G.GraphStructuredValue Block blockTypes Operator
        context bound output
  | 0, .nil, index => Fin.elim0 index
  | _ + 1, .cons head tail, ⟨0, _⟩ => head
  | _ + 1, .cons head tail, ⟨index + 1, bounded⟩ =>
      get tail ⟨index, by omega⟩

/-- Lookup commutes with the outer-context action. -/
theorem get_act {Block : Type y} {blockTypes : Block → List Ty}
    {Operator : Ty → Type z}
    {source target : TypedSlotContext.{u, w} Ty}
    (outer : TypedSlotEmbedding source target) {bound : List Ty} {output : Ty}
    {size : Nat}
    (forest : G.GraphStructuredForest Block blockTypes Operator
      source bound output size) (index : Fin size) :
    get G (GraphStructuredValue.GraphStructuredForest.act G outer forest) index =
      GraphStructuredValue.act G outer (get G forest index) := by
  cases forest with
  | nil => exact Fin.elim0 index
  | cons head tail =>
      rcases index with ⟨index, bounded⟩
      cases index with
      | zero => rfl
      | succ index => exact get_act outer tail ⟨index, by omega⟩
termination_by size

end GraphStructuredValue.GraphStructuredForest

/-- A proof-relevant occurrence permutation for a bag of fixed size. -/
structure FiniteIndexPermutation (size : Nat) where
  toFun : Fin size → Fin size
  inverse : Fin size → Fin size
  leftInverse : ∀ index, inverse (toFun index) = index
  rightInverse : ∀ index, toFun (inverse index) = index

/-- Full graph-relative structural alignment.  Sequence children align by
    position; bags use an occurrence bijection; sets use mutual mate coverage;
    binders preserve the free-context alignment, and blocks carry only an
    explicitly admitted descriptor automorphism. -/
inductive GraphStructuredAlignedBy
    (graph : QuiescentFiniteTypedEGraph Ty ClassId Shape classOutput
      shapeOutput interface)
    (Block : Type y) (blockTypes : Block → List Ty)
    (BlockAutomorphism : Block → Type z) (Operator : Ty → Type z)
    {source target : TypedSlotContext.{u, w} Ty}
    (alignment : TypedSlotRenaming source target) {output : Ty} :
    {bound : List Ty} →
    graph.GraphStructuredValue Block blockTypes Operator source bound output →
    graph.GraphStructuredValue Block blockTypes Operator target bound output →
    Prop where
  | free {leftSlot : source.Slot} {rightSlot : target.Slot}
      (leftTyped : source.typeOf leftSlot = output)
      (rightTyped : target.typeOf rightSlot = output)
      (aligned : alignment.toTypedSlotEmbedding.toFun leftSlot = rightSlot) :
      GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
        alignment (.free leftSlot leftTyped) (.free rightSlot rightTyped)
  | invocation
      {left : graph.GraphInvocation source}
      {right : graph.GraphInvocation target}
      (leftTyped : classOutput left.classId = output)
      (rightTyped : classOutput right.classId = output)
      (aligned : graph.GraphInvocationAlignedBy alignment left right) :
      GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
        alignment (.invocation left leftTyped) (.invocation right rightTyped)
  | sequence {size : Nat}
      {left : graph.GraphStructuredForest Block blockTypes Operator
        source bound output size}
      {right : graph.GraphStructuredForest Block blockTypes Operator
        target bound output size}
      (children : ∀ index,
        GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
          alignment (GraphStructuredValue.GraphStructuredForest.get graph left index)
            (GraphStructuredValue.GraphStructuredForest.get graph right index)) :
      GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
        alignment (.sequence left) (.sequence right)
  | bag {size : Nat}
      {left : graph.GraphStructuredForest Block blockTypes Operator
        source bound output size}
      {right : graph.GraphStructuredForest Block blockTypes Operator
        target bound output size}
      (permutation : FiniteIndexPermutation size)
      (occurrences : ∀ index,
        GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
          alignment (GraphStructuredValue.GraphStructuredForest.get graph left index)
            (GraphStructuredValue.GraphStructuredForest.get graph right
              (permutation.toFun index))) :
      GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
        alignment (.bag left) (.bag right)
  | set {leftSize rightSize : Nat}
      {left : graph.GraphStructuredForest Block blockTypes Operator
        source bound output leftSize}
      {right : graph.GraphStructuredForest Block blockTypes Operator
        target bound output rightSize}
      (forwardIndex : Fin leftSize → Fin rightSize)
      (forward : ∀ leftIndex,
        GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
          alignment (GraphStructuredValue.GraphStructuredForest.get graph left leftIndex)
            (GraphStructuredValue.GraphStructuredForest.get graph right
              (forwardIndex leftIndex)))
      (backwardIndex : Fin rightSize → Fin leftSize)
      (backward : ∀ rightIndex,
        GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
          alignment (GraphStructuredValue.GraphStructuredForest.get graph left
            (backwardIndex rightIndex))
            (GraphStructuredValue.GraphStructuredForest.get graph right rightIndex)) :
      GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
        alignment (.set left) (.set right)
  | binder (boundType : Ty)
      {left : graph.GraphStructuredValue Block blockTypes Operator source
        (boundType :: bound) output}
      {right : graph.GraphStructuredValue Block blockTypes Operator target
        (boundType :: bound) output}
      (body : GraphStructuredAlignedBy graph Block blockTypes
        BlockAutomorphism Operator alignment left right) :
      GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
        alignment (.binder boundType left) (.binder boundType right)
  | binderBlock (descriptor : Block) (automorphism : BlockAutomorphism descriptor)
      {left : graph.GraphStructuredValue Block blockTypes Operator source
        (blockTypes descriptor ++ bound) output}
      {right : graph.GraphStructuredValue Block blockTypes Operator target
        (blockTypes descriptor ++ bound) output}
      (body : GraphStructuredAlignedBy graph Block blockTypes
        BlockAutomorphism Operator alignment left right) :
      GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
        alignment (.binderBlock descriptor left) (.binderBlock descriptor right)
  | node {size : Nat} (operator : Operator output)
      {left : graph.GraphStructuredForest Block blockTypes Operator
        source bound output size}
      {right : graph.GraphStructuredForest Block blockTypes Operator
        target bound output size}
      (children : ∀ index,
        GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
          alignment (GraphStructuredValue.GraphStructuredForest.get graph left index)
            (GraphStructuredValue.GraphStructuredForest.get graph right index)) :
      GraphStructuredAlignedBy graph Block blockTypes BlockAutomorphism Operator
        alignment (.node operator left) (.node operator right)

end QuiescentFiniteTypedEGraph

end TypedSlottedEGraphsPaper
