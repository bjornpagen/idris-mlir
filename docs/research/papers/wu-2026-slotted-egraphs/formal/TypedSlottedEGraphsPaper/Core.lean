import Std

namespace TypedSlottedEGraphsPaper

universe u v w x

/-- A finite paper context, represented abstractly by typed slots.  Finiteness is
    carried as data so later algorithms may enumerate without changing the
    meaning of an embedding. -/
structure TypedSlotContext (Ty : Type u) where
  Slot : Type v
  typeOf : Slot → Ty
  cardinalityBound : Nat
  encode : Slot → Fin cardinalityBound
  encodeInjective : Function.Injective encode

/-- A type-preserving injection between the stated source and target contexts. -/
structure TypedSlotEmbedding {Ty : Type u}
    (S T : TypedSlotContext.{u, v} Ty) where
  toFun : S.Slot → T.Slot
  injective : Function.Injective toFun
  preservesType : ∀ s, T.typeOf (toFun s) = S.typeOf s

namespace TypedSlotEmbedding

def id {Ty : Type u} (S : TypedSlotContext.{u, v} Ty) :
    TypedSlotEmbedding S S where
  toFun := _root_.id
  injective := Function.injective_id
  preservesType := by intro s; rfl

def comp {Ty : Type u} {R S T : TypedSlotContext.{u, v} Ty}
    (e : TypedSlotEmbedding S T) (m : TypedSlotEmbedding R S) :
    TypedSlotEmbedding R T where
  toFun := e.toFun ∘ m.toFun
  injective := e.injective.comp m.injective
  preservesType := by
    intro r
    exact (e.preservesType (m.toFun r)).trans (m.preservesType r)

@[simp] theorem id_apply {Ty : Type u} {S : TypedSlotContext.{u, v} Ty}
    (s : S.Slot) : (id S).toFun s = s := rfl

@[simp] theorem comp_apply {Ty : Type u}
    {R S T : TypedSlotContext.{u, v} Ty}
    (e : TypedSlotEmbedding S T) (m : TypedSlotEmbedding R S) (r : R.Slot) :
    (comp e m).toFun r = e.toFun (m.toFun r) := rfl

theorem ext {Ty : Type u} {S T : TypedSlotContext.{u, v} Ty}
    {e m : TypedSlotEmbedding S T} (h : ∀ s, e.toFun s = m.toFun s) : e = m := by
  cases e with
  | mk ef ei et =>
    cases m with
    | mk mf mi mt =>
      have : ef = mf := funext h
      cases this
      rfl

theorem comp_id {Ty : Type u} {S T : TypedSlotContext.{u, v} Ty}
    (e : TypedSlotEmbedding S T) : comp e (id S) = e := by
  apply ext
  intro s
  rfl

theorem id_comp {Ty : Type u} {S T : TypedSlotContext.{u, v} Ty}
    (e : TypedSlotEmbedding S T) : comp (id T) e = e := by
  apply ext
  intro s
  rfl

theorem comp_assoc {Ty : Type u}
    {Q R S T : TypedSlotContext.{u, v} Ty}
    (e : TypedSlotEmbedding S T) (m : TypedSlotEmbedding R S)
    (k : TypedSlotEmbedding Q R) :
    comp (comp e m) k = comp e (comp m k) := by
  apply ext
  intro q
  rfl

theorem range_comp_subset {Ty : Type u}
    {R S T : TypedSlotContext.{u, v} Ty}
    (e : TypedSlotEmbedding S T) (m : TypedSlotEmbedding R S) :
    ∀ {t}, (∃ r, (comp e m).toFun r = t) → ∃ s, e.toFun s = t := by
  intro t ht
  rcases ht with ⟨r, rfl⟩
  exact ⟨m.toFun r, rfl⟩

end TypedSlotEmbedding

/-- A typed renaming is an embedding with a typed inverse. -/
structure TypedSlotRenaming {Ty : Type u}
    (S T : TypedSlotContext.{u, v} Ty) extends TypedSlotEmbedding S T where
  inverse : TypedSlotEmbedding T S
  leftInverse : TypedSlotEmbedding.comp inverse toTypedSlotEmbedding =
    TypedSlotEmbedding.id S
  rightInverse : TypedSlotEmbedding.comp toTypedSlotEmbedding inverse =
    TypedSlotEmbedding.id T

namespace TypedSlotRenaming

theorem ext {Ty : Type u} {S T : TypedSlotContext.{u, v} Ty}
    {ρ σ : TypedSlotRenaming S T}
    (h : ρ.toTypedSlotEmbedding = σ.toTypedSlotEmbedding) : ρ = σ := by
  cases ρ with
  | mk re ri rl rr =>
    cases σ with
    | mk se si sl sr =>
      cases h
      have hi : ri = si := by
        apply TypedSlotEmbedding.ext
        intro t
        have hleft := congrArg (fun e => e.toFun (ri.toFun t)) sl
        have hright := congrArg (fun e => e.toFun t) rr
        exact hleft.symm.trans (congrArg si.toFun hright)
      cases hi
      rfl

def id {Ty : Type u} (S : TypedSlotContext.{u, v} Ty) :
    TypedSlotRenaming S S where
  toTypedSlotEmbedding := TypedSlotEmbedding.id S
  inverse := TypedSlotEmbedding.id S
  leftInverse := TypedSlotEmbedding.comp_id _
  rightInverse := TypedSlotEmbedding.comp_id _

def symm {Ty : Type u} {S T : TypedSlotContext.{u, v} Ty}
    (ρ : TypedSlotRenaming S T) : TypedSlotRenaming T S where
  toTypedSlotEmbedding := ρ.inverse
  inverse := ρ.toTypedSlotEmbedding
  leftInverse := ρ.rightInverse
  rightInverse := ρ.leftInverse

def comp {Ty : Type u} {R S T : TypedSlotContext.{u, v} Ty}
    (ρ : TypedSlotRenaming S T) (σ : TypedSlotRenaming R S) :
    TypedSlotRenaming R T where
  toTypedSlotEmbedding := TypedSlotEmbedding.comp
    ρ.toTypedSlotEmbedding σ.toTypedSlotEmbedding
  inverse := TypedSlotEmbedding.comp σ.inverse ρ.inverse
  leftInverse := by
    apply TypedSlotEmbedding.ext
    intro r
    have hσ := congrArg (fun e => e.toFun r) σ.leftInverse
    have hρ := congrArg (fun e => e.toFun (σ.toTypedSlotEmbedding.toFun r)) ρ.leftInverse
    exact (congrArg σ.inverse.toFun hρ).trans hσ
  rightInverse := by
    apply TypedSlotEmbedding.ext
    intro t
    have hρ := congrArg (fun e => e.toFun t) ρ.rightInverse
    have hσ := congrArg (fun e => e.toFun (ρ.inverse.toFun t)) σ.rightInverse
    exact (congrArg ρ.toTypedSlotEmbedding.toFun hσ).trans hρ

theorem symm_comp {Ty : Type u} {S T : TypedSlotContext.{u, v} Ty}
    (ρ : TypedSlotRenaming S T) : comp (symm ρ) ρ = id S := by
  apply ext
  exact ρ.leftInverse

theorem comp_symm {Ty : Type u} {S T : TypedSlotContext.{u, v} Ty}
    (ρ : TypedSlotRenaming S T) : comp ρ (symm ρ) = id T := by
  apply ext
  exact ρ.rightInverse

theorem comp_id {Ty : Type u} {S T : TypedSlotContext.{u, v} Ty}
    (ρ : TypedSlotRenaming S T) : comp ρ (id S) = ρ := by
  apply ext
  exact TypedSlotEmbedding.comp_id _

theorem id_comp {Ty : Type u} {S T : TypedSlotContext.{u, v} Ty}
    (ρ : TypedSlotRenaming S T) : comp (id T) ρ = ρ := by
  apply ext
  exact TypedSlotEmbedding.id_comp _

theorem comp_assoc {Ty : Type u}
    {Q R S T : TypedSlotContext.{u, v} Ty}
    (ρ : TypedSlotRenaming S T) (σ : TypedSlotRenaming R S)
    (κ : TypedSlotRenaming Q R) :
    comp (comp ρ σ) κ = comp ρ (comp σ κ) := by
  apply ext
  exact TypedSlotEmbedding.comp_assoc _ _ _

end TypedSlotRenaming

/-- The three sibling carriers used by flexible-arity ports. -/
inductive ContainerKind where
  | seq
  | bag
  | set
  deriving DecidableEq, Repr

/-- A nonempty arity license, kept separate from algebraic law licenses. -/
structure ArityLicense where
  admits : Nat → Prop
  hasArity : ∃ n, admits n

/-- Paper port grammar: one typed value, a licensed container, a unary
    binder, or a descriptor-governed binder block. -/
inductive PortSchema (Ty : Type u) (Descriptor : Type v) where
  | one (output : Ty)
  | container (kind : ContainerKind) (arity : ArityLicense)
      (element : PortSchema Ty Descriptor)
  | bind (boundType : Ty) (body : PortSchema Ty Descriptor)
  | bindBlock (descriptor : Descriptor) (body : PortSchema Ty Descriptor)

/-- A signature-admitted node carries all port values and an independently
    checked typing witness. -/
structure TypedFlexibleArityENode (Op : Type u) (Ty : Type v) (Port : Type w) where
  operator : Op
  ports : List Port
  output : Ty
  typingWitness : Prop
  typingChecked : typingWitness

/-- An invocation records its callee together with a typed embedding of the
    callee interface into the caller context. -/
structure Invocation {Ty : Type u} (ClassId : Type w)
    (interface : ClassId → TypedSlotContext.{u, v} Ty)
    (caller : TypedSlotContext.{u, v} Ty) where
  classId : ClassId
  embedding : TypedSlotEmbedding (interface classId) caller

/-- The quiescent abstract state.  Stored keys and collision buckets are
    separated from the parent forest so equal keys need not force a union. -/
structure FlexibleArityTypedSlottedEGraph
    (Ty : Type u) (SlotPayload : Type v) (ClassId : Type w) (Shape : Type x) where
  classOutput : ClassId → Ty
  classInterface : ClassId → SlotPayload
  parent : ClassId → ClassId
  isLeader : ClassId → Prop
  storedShape : ClassId → Shape → Prop
  collisionOwner : Shape → ClassId → Prop
  parentForest : Prop
  liveOwnersIndexed : Prop
  parentForestChecked : parentForest
  liveOwnersIndexedChecked : liveOwnersIndexed

/-- A context-indexed, type-preserving renaming action. -/
structure AlphaGroupoidAction {Ty : Type u}
    (Carrier : TypedSlotContext.{u, v} Ty → Type w) where
  act : {Γ Δ : TypedSlotContext.{u, v} Ty} →
    TypedSlotRenaming Γ Δ → Carrier Γ → Carrier Δ
  actId : ∀ {Γ} (x : Carrier Γ), act (TypedSlotRenaming.id Γ) x = x
  actComp : ∀ {Γ Δ Ξ} (ρ : TypedSlotRenaming Γ Δ)
    (σ : TypedSlotRenaming Δ Ξ) (x : Carrier Γ),
    act (TypedSlotRenaming.comp σ ρ) x = act σ (act ρ x)

/-- Typed alpha-equivalence is existence of a type-preserving alignment
    carrying one value to the other. -/
def TypedAlphaEquivalenceOfPortValues {Ty : Type u}
    {Carrier : TypedSlotContext.{u, v} Ty → Type w}
    (A : AlphaGroupoidAction Carrier) {Γ Δ : TypedSlotContext.{u, v} Ty}
    (x : Carrier Γ) (y : Carrier Δ) : Prop :=
  ∃ ρ : TypedSlotRenaming Γ Δ, A.act ρ x = y

end TypedSlottedEGraphsPaper
