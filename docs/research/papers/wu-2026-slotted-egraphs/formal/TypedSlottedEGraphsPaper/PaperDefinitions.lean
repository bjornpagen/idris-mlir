import TypedSlottedEGraphsPaper.SyntaxSupport

namespace TypedSlottedEGraphsPaper

universe u v w x y z

/-- F02 contract: canonicalization chooses a typed context with a checked
    type-preserving bijection back to the original context.  An instantiation
    additionally fixes its reserved ordered alphabets. -/
structure CanonicalTypedContextDefinition (Ty : Type u) where
  canonical : TypedSlotContext.{u, v} Ty → TypedSlotContext.{u, v} Ty
  alignment : ∀ Γ, TypedSlotRenaming (canonical Γ) Γ

/-- One declaration bundling the complete F03 embedding, renaming, and
    permutation definition together with its operations. -/
structure TypedEmbeddingRenamingDefinition (Ty : Type u) where
  Embedding : TypedSlotContext.{u, v} Ty → TypedSlotContext.{u, v} Ty → Type v
  Renaming : TypedSlotContext.{u, v} Ty → TypedSlotContext.{u, v} Ty → Type v
  Permutation : TypedSlotContext.{u, v} Ty → Type v
  identity : ∀ S, Embedding S S
  compose : ∀ {R S T}, Embedding S T → Embedding R S → Embedding R T
  inverse : ∀ {S T}, Renaming S T → Renaming T S
  permutationIsSelfRenaming : ∀ S, Permutation S = Renaming S S

/-- The exact paper instantiation of the F03 bundle. -/
def paperTypedEmbeddingRenamingDefinition (Ty : Type u) :
    TypedEmbeddingRenamingDefinition.{u, v} Ty where
  Embedding := TypedSlotEmbedding
  Renaming := TypedSlotRenaming
  Permutation := fun S => TypedSlotRenaming S S
  identity := TypedSlotEmbedding.id
  compose := TypedSlotEmbedding.comp
  inverse := TypedSlotRenaming.symm
  permutationIsSelfRenaming := fun _ => rfl

/-- F05 as one dependent carrier: a value packages its exact port schema and
    a recursively typed concrete value at that schema. -/
abbrev TypedPortSchemaAndValueDefinition
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    (context : TypedSlotContext.{u, v} Ty) (bound : List Ty) :=
  Sigma fun schema : PortSchema Ty Descriptor =>
    ConcretePort signature context bound schema

/-- F06 bundles an intrinsically typed concrete node with its uniquely
    derived free-support predicate. -/
structure TypedENodeAndSupportDefinition
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    (context : TypedSlotContext.{u, v} Ty) (output : Ty) where
  node : ConcreteFlexibleArityENode signature context output
  support : context.Slot → Prop
  supportExact : support = ConcreteFlexibleArityENode.Supports node

/-- F10 graph state with typed parent embeddings, a checked forest/find
    interface, live stored shapes, collision buckets, and an explicit
    quiescence condition. -/
structure QuiescentTypedEGraphDefinition
    (Ty : Type u) (ClassId : Type w) (Shape : Type x) where
  interface : ClassId → TypedSlotContext.{u, v} Ty
  output : ClassId → Ty
  parent : ClassId → ClassId
  parentEmbedding : ∀ a,
    TypedSlotEmbedding (interface (parent a)) (interface a)
  isLeader : ClassId → Prop
  rootFixed : ∀ {a}, isLeader a → parent a = a
  ParentPath : ClassId → ClassId → Type y
  pathEmbedding : ∀ {a leader}, ParentPath a leader →
    TypedSlotEmbedding (interface leader) (interface a)
  findLeader : ClassId → ClassId
  findIsLeader : ∀ a, isLeader (findLeader a)
  findPath : ∀ a, ParentPath a (findLeader a)
  storedShape : ClassId → Shape → Prop
  collisionOwner : Shape → ClassId → Prop
  quiescent : Prop
  collisionIndexExact : quiescent → ∀ shape owner,
    collisionOwner shape owner ↔ isLeader owner ∧ storedShape owner shape

/-- F12 is an indexed relation, independent of denotational equality.  The
    seven constructor families make the atomic, invocation, sequence, bag,
    set, binder, binder-block, and node clauses identifiable obligations. -/
structure AbstractIndexedStructuralAlphaDefinition
    (Ty : Type u) (Schema : Type x) where
  Carrier : TypedSlotContext.{u, v} Ty → Schema → Type w
  relation : {Γ Δ : TypedSlotContext.{u, v} Ty} → {κ : Schema} →
    TypedSlotRenaming Γ Δ → Carrier Γ κ → Carrier Δ κ → Prop
  AtomicClause : {Γ Δ : TypedSlotContext.{u, v} Ty} → {κ : Schema} →
    TypedSlotRenaming Γ Δ → Carrier Γ κ → Carrier Δ κ → Prop
  InvocationClause : {Γ Δ : TypedSlotContext.{u, v} Ty} → {κ : Schema} →
    TypedSlotRenaming Γ Δ → Carrier Γ κ → Carrier Δ κ → Prop
  SequenceClause : {Γ Δ : TypedSlotContext.{u, v} Ty} → {κ : Schema} →
    TypedSlotRenaming Γ Δ → Carrier Γ κ → Carrier Δ κ → Prop
  BagClause : {Γ Δ : TypedSlotContext.{u, v} Ty} → {κ : Schema} →
    TypedSlotRenaming Γ Δ → Carrier Γ κ → Carrier Δ κ → Prop
  SetClause : {Γ Δ : TypedSlotContext.{u, v} Ty} → {κ : Schema} →
    TypedSlotRenaming Γ Δ → Carrier Γ κ → Carrier Δ κ → Prop
  BinderClause : {Γ Δ : TypedSlotContext.{u, v} Ty} → {κ : Schema} →
    TypedSlotRenaming Γ Δ → Carrier Γ κ → Carrier Δ κ → Prop
  BinderBlockClause : {Γ Δ : TypedSlotContext.{u, v} Ty} → {κ : Schema} →
    TypedSlotRenaming Γ Δ → Carrier Γ κ → Carrier Δ κ → Prop
  NodeClause : {Γ Δ : TypedSlotContext.{u, v} Ty} → {κ : Schema} →
    TypedSlotRenaming Γ Δ → Carrier Γ κ → Carrier Δ κ → Prop
  relationGenerated : ∀ {Γ Δ κ} {ρ : TypedSlotRenaming Γ Δ}
    {left : Carrier Γ κ} {right : Carrier Δ κ},
    relation ρ left right ↔
      AtomicClause ρ left right ∨ InvocationClause ρ left right ∨
      SequenceClause ρ left right ∨ BagClause ρ left right ∨
      SetClause ρ left right ∨ BinderClause ρ left right ∨
      BinderBlockClause ρ left right ∨ NodeClause ρ left right

end TypedSlottedEGraphsPaper
