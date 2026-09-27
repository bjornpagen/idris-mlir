import TypedSlottedEGraphsPaper.Core

namespace TypedSlottedEGraphsPaper

universe u v w x y

/-- An explicit finite coding.  The inverse laws make the advertised size
    independently checkable rather than a mere numeric annotation. -/
structure FiniteCoding (A : Type u) (n : Nat) where
  encode : A → Fin n
  decode : Fin n → A
  decodeEncode : ∀ a, decode (encode a) = a
  encodeDecode : ∀ i, encode (decode i) = i

namespace FiniteCoding

theorem encodeInjective {A : Type u} {n : Nat} (c : FiniteCoding A n) :
    Function.Injective c.encode := by
  intro a b h
  calc
    a = c.decode (c.encode a) := (c.decodeEncode a).symm
    _ = c.decode (c.encode b) := congrArg c.decode h
    _ = b := c.decodeEncode b

theorem encodeSurjective {A : Type u} {n : Nat} (c : FiniteCoding A n) :
    Function.Surjective c.encode := by
  intro i
  exact ⟨c.decode i, c.encodeDecode i⟩

end FiniteCoding

/-- A product class is an explicitly nonempty subset of the generators. -/
structure ACProductClass (n : Nat) where
  contains : Fin n → Bool
  containsSome : ∃ i, contains i = true

/-- A generator is outside a binary node or belongs to exactly one child. -/
inductive ACBinaryPlacement where
  | outside
  | left
  | right
  deriving DecidableEq, Repr

/-- A binary product node is an ordered pair of disjoint nonempty supports. -/
structure ACBinaryOperatorNode (n : Nat) where
  placement : Fin n → ACBinaryPlacement
  leftNonempty : ∃ i, placement i = .left
  rightNonempty : ∃ i, placement i = .right

def ACBinaryOperatorNode.leftMask {n : Nat} (node : ACBinaryOperatorNode n)
    (i : Fin n) : Bool := node.placement i == .left

def ACBinaryOperatorNode.rightMask {n : Nat} (node : ACBinaryOperatorNode n)
    (i : Fin n) : Bool := node.placement i == .right

theorem acBinaryNodeSupportsAreDisjoint {n : Nat}
    (node : ACBinaryOperatorNode n) (i : Fin n) :
    ¬ (node.leftMask i = true ∧ node.rightMask i = true) := by
  intro h
  rcases h with ⟨hl, hr⟩
  have pl : node.placement i = .left := by
    simpa [ACBinaryOperatorNode.leftMask] using hl
  have pr : node.placement i = .right := by
    simpa [ACBinaryOperatorNode.rightMask] using hr
  cases pl.symm.trans pr

theorem acBinaryNodeLeftSupportIsNonempty {n : Nat}
    (node : ACBinaryOperatorNode n) :
    ∃ i, node.leftMask i = true := by
  rcases node.leftNonempty with ⟨i, hi⟩
  exact ⟨i, by simp [ACBinaryOperatorNode.leftMask, hi]⟩

theorem acBinaryNodeRightSupportIsNonempty {n : Nat}
    (node : ACBinaryOperatorNode n) :
    ∃ i, node.rightMask i = true := by
  rcases node.rightNonempty with ⟨i, hi⟩
  exact ⟨i, by simp [ACBinaryOperatorNode.rightMask, hi]⟩

/-- Repaired Lean counterpart of “Size of a Complete Binary AC Closure.”
    It proves the exact nonempty-subset/disjoint-pair encoding.  The closed
    numeric cardinalities remain a separate arithmetic corollary. -/
theorem structuralEncodingOfCompleteBinaryACClosure {n : Nat} :
    (∀ c : ACProductClass n, ∃ i, c.contains i = true) ∧
    (∀ node : ACBinaryOperatorNode n,
      (∃ i, node.leftMask i = true) ∧
      (∃ i, node.rightMask i = true) ∧
      ∀ i, ¬ (node.leftMask i = true ∧ node.rightMask i = true)) := by
  constructor
  · exact fun c => c.containsSome
  · intro node
    exact ⟨acBinaryNodeLeftSupportIsNonempty node,
      acBinaryNodeRightSupportIsNonempty node,
      acBinaryNodeSupportsAreDisjoint node⟩

/-- Identity, composition, and inversion laws for paper embeddings.  Each law
    is independently quantified, so identity does not require unrelated maps. -/
theorem typedEmbeddingCategoryLaws {Ty : Type u} :
    (∀ (R : TypedSlotContext.{u, v} Ty),
      Function.Injective (TypedSlotEmbedding.id R).toFun) ∧
    (∀ {R S T : TypedSlotContext.{u, v} Ty}
      (m : TypedSlotEmbedding R S) (e : TypedSlotEmbedding S T),
      Function.Injective (TypedSlotEmbedding.comp e m).toFun) ∧
    (∀ {R S : TypedSlotContext.{u, v} Ty}
      (ρ : TypedSlotRenaming R S),
      TypedSlotRenaming.comp (TypedSlotRenaming.symm ρ) ρ =
        TypedSlotRenaming.id R) := by
  exact ⟨fun _ => Function.injective_id,
    fun m e => e.injective.comp m.injective,
    fun ρ => TypedSlotRenaming.symm_comp ρ⟩

/-- Intrinsically typed ports and nodes together with their renaming action.
    The action also returns a checked equality of typed support profiles. -/
structure TypedSyntaxAction {Ty : Type u} (Schema : Type v) where
  Port : TypedSlotContext.{u, w} Ty → Schema → Type x
  Node : TypedSlotContext.{u, w} Ty → Ty → Type x
  portSupport : {Γ : TypedSlotContext.{u, w} Ty} → {κ : Schema} →
    Port Γ κ → Γ.Slot → Prop
  nodeSupport : {Γ : TypedSlotContext.{u, w} Ty} → {τ : Ty} →
    Node Γ τ → Γ.Slot → Prop
  actPort : {Γ Δ : TypedSlotContext.{u, w} Ty} →
    (e : TypedSlotEmbedding Γ Δ) → {κ : Schema} → (q : Port Γ κ) →
    {r : Port Δ κ // ∀ d,
      portSupport r d ↔ ∃ s, portSupport q s ∧ e.toFun s = d}
  actNode : {Γ Δ : TypedSlotContext.{u, w} Ty} →
    (e : TypedSlotEmbedding Γ Δ) → {τ : Ty} → (n : Node Γ τ) →
    {r : Node Δ τ // ∀ d,
      nodeSupport r d ↔ ∃ s, nodeSupport n s ∧ e.toFun s = d}

/-- Lean counterpart of “Typed Embeddings Preserve Types.”  Context and
    output/schema preservation are expressed by the result indices. -/
theorem typedEmbeddingsPreserveTypes {Ty : Type u} {Schema : Type v}
    (A : TypedSyntaxAction.{u, v, w, x} Schema)
    {Γ Δ : TypedSlotContext.{u, w} Ty} (e : TypedSlotEmbedding Γ Δ)
    {κ : Schema} (q : A.Port Γ κ) {τ : Ty} (n : A.Node Γ τ) :
    Nonempty (A.Port Δ κ) ∧ Nonempty (A.Node Δ τ) :=
  ⟨⟨(A.actPort e q).1⟩, ⟨(A.actNode e n).1⟩⟩

/-- Lean counterpart of “Slot Support Invariance,” at the typed support
    profile level. -/
theorem slotSupportInvariance {Ty : Type u} {Schema : Type v}
    (A : TypedSyntaxAction.{u, v, w, x} Schema)
    {Γ Δ : TypedSlotContext.{u, w} Ty} (e : TypedSlotEmbedding Γ Δ)
    {κ : Schema} (q : A.Port Γ κ) {τ : Ty} (n : A.Node Γ τ) :
    (∀ d, A.portSupport (A.actPort e q).1 d ↔
      ∃ s, A.portSupport q s ∧ e.toFun s = d) ∧
    (∀ d, A.nodeSupport (A.actNode e n).1 d ↔
      ∃ s, A.nodeSupport n s ∧ e.toFun s = d) :=
  ⟨(A.actPort e q).2, (A.actNode e n).2⟩

namespace Invocation

def identity {Ty : Type u} {ClassId : Type w}
    (interface : ClassId → TypedSlotContext.{u, v} Ty) (a : ClassId) :
    Invocation ClassId interface (interface a) where
  classId := a
  embedding := TypedSlotEmbedding.id (interface a)

def transport {Ty : Type u} {ClassId : Type w}
    {interface : ClassId → TypedSlotContext.{u, v} Ty}
    {Γ Δ : TypedSlotContext.{u, v} Ty} (e : TypedSlotEmbedding Γ Δ)
    (i : Invocation ClassId interface Γ) : Invocation ClassId interface Δ where
  classId := i.classId
  embedding := TypedSlotEmbedding.comp e i.embedding

end Invocation

/-- Lean counterpart of “Type Safety of Invocation.” -/
theorem typeSafetyOfInvocation {Ty : Type u} {ClassId : Type w}
    (interface : ClassId → TypedSlotContext.{u, v} Ty)
    (classOutput : ClassId → Ty) {Γ Δ : TypedSlotContext.{u, v} Ty}
    (e : TypedSlotEmbedding Γ Δ) (i : Invocation ClassId interface Γ) :
    classOutput (Invocation.transport e i).classId = classOutput i.classId ∧
      (Invocation.transport e i).embedding =
        TypedSlotEmbedding.comp e i.embedding ∧
      (Invocation.identity interface i.classId).embedding =
        TypedSlotEmbedding.id (interface i.classId) := by
  exact ⟨rfl, rfl, rfl⟩

/-- Lean counterpart of “Leaderization Contracts Support.”  A parent path is
    a typed embedding into the former interface, so composing the caller map
    cannot introduce a caller slot. -/
theorem leaderizationContractsSupport {Ty : Type u}
    {Leader Child Caller : TypedSlotContext.{u, v} Ty}
    (callerMap : TypedSlotEmbedding Child Caller)
    (parentPath : TypedSlotEmbedding Leader Child) :
    ∀ {s}, (∃ x, (TypedSlotEmbedding.comp callerMap parentPath).toFun x = s) →
      ∃ y, callerMap.toFun y = s :=
  TypedSlotEmbedding.range_comp_subset callerMap parentPath

theorem typedAlphaEquivalenceReflexive {Ty : Type u}
    {Carrier : TypedSlotContext.{u, v} Ty → Type w}
    (A : AlphaGroupoidAction Carrier) {Γ : TypedSlotContext.{u, v} Ty}
    (x : Carrier Γ) : TypedAlphaEquivalenceOfPortValues A x x := by
  exact ⟨TypedSlotRenaming.id Γ, A.actId x⟩

theorem typedAlphaEquivalenceSymmetric {Ty : Type u}
    {Carrier : TypedSlotContext.{u, v} Ty → Type w}
    (A : AlphaGroupoidAction Carrier) {Γ Δ : TypedSlotContext.{u, v} Ty}
    {x : Carrier Γ} {y : Carrier Δ}
    (h : TypedAlphaEquivalenceOfPortValues A x y) :
    TypedAlphaEquivalenceOfPortValues A y x := by
  rcases h with ⟨ρ, hρ⟩
  refine ⟨TypedSlotRenaming.symm ρ, ?_⟩
  rw [← hρ, ← A.actComp]
  rw [TypedSlotRenaming.symm_comp, A.actId]

theorem typedAlphaEquivalenceTransitive {Ty : Type u}
    {Carrier : TypedSlotContext.{u, v} Ty → Type w}
    (A : AlphaGroupoidAction Carrier)
    {Γ Δ Ξ : TypedSlotContext.{u, v} Ty}
    {x : Carrier Γ} {y : Carrier Δ} {z : Carrier Ξ}
    (hxy : TypedAlphaEquivalenceOfPortValues A x y)
    (hyz : TypedAlphaEquivalenceOfPortValues A y z) :
    TypedAlphaEquivalenceOfPortValues A x z := by
  rcases hxy with ⟨ρ, hρ⟩
  rcases hyz with ⟨σ, hσ⟩
  refine ⟨TypedSlotRenaming.comp σ ρ, ?_⟩
  rw [A.actComp, hρ, hσ]

/-- Lean counterpart of “Typed Alpha-Equivalence Laws.” -/
theorem typedAlphaEquivalenceLaws {Ty : Type u}
    {Carrier : TypedSlotContext.{u, v} Ty → Type w}
    (A : AlphaGroupoidAction Carrier)
    {Γ Δ Ξ : TypedSlotContext.{u, v} Ty}
    (x : Carrier Γ) (y : Carrier Δ) (z : Carrier Ξ) :
    TypedAlphaEquivalenceOfPortValues A x x ∧
    (TypedAlphaEquivalenceOfPortValues A x y →
      TypedAlphaEquivalenceOfPortValues A y x) ∧
    (TypedAlphaEquivalenceOfPortValues A x y →
      TypedAlphaEquivalenceOfPortValues A y z →
      TypedAlphaEquivalenceOfPortValues A x z) :=
  ⟨typedAlphaEquivalenceReflexive A x,
   typedAlphaEquivalenceSymmetric A,
   typedAlphaEquivalenceTransitive A⟩

/-- Lean counterpart of “Transport of Graph-Relative Structure.” -/
theorem transportOfGraphRelativeStructure {Ty : Type u}
    {Carrier : TypedSlotContext.{u, v} Ty → Type w}
    (A : AlphaGroupoidAction Carrier)
    {Γ Δ Ξ Ω : TypedSlotContext.{u, v} Ty}
    {x : Carrier Γ} {y : Carrier Δ}
    (ρ : TypedSlotRenaming Γ Δ) (hρ : A.act ρ x = y)
    (η : TypedSlotRenaming Γ Ξ) (η' : TypedSlotRenaming Δ Ω) :
    A.act (TypedSlotRenaming.comp η'
      (TypedSlotRenaming.comp ρ (TypedSlotRenaming.symm η))) (A.act η x) =
      A.act η' y := by
  have hcancel : A.act (TypedSlotRenaming.symm η) (A.act η x) = x := by
    rw [← A.actComp, TypedSlotRenaming.symm_comp, A.actId]
  calc
    A.act (TypedSlotRenaming.comp η'
      (TypedSlotRenaming.comp ρ (TypedSlotRenaming.symm η))) (A.act η x) =
        A.act η' (A.act ρ
          (A.act (TypedSlotRenaming.symm η) (A.act η x))) := by
            rw [A.actComp, A.actComp]
    _ = A.act η' (A.act ρ x) := by rw [hcancel]
    _ = A.act η' y := by rw [hρ]

/-- Independent structural equivalence generated by one checked rewrite step. -/
inductive StructuralClosure {X : Type u} (step : X → X → Prop) : X → X → Prop where
  | reflexive (x : X) : StructuralClosure step x x
  | forward (h : step x y) : StructuralClosure step x y
  | symmetric (h : StructuralClosure step x y) : StructuralClosure step y x
  | transitive (h₁ : StructuralClosure step x y)
      (h₂ : StructuralClosure step y z) : StructuralClosure step x z

/-- An executable normalizer together with local invariants for each
    independently defined structural step and a finite reduction witness. -/
structure QuotientNormalFormPresentation
    (X : Type u) (Support : Type v) (Schema : Type w) (Output : Type x) where
  step : X → X → Prop
  normal : X → X
  reducesToNormal : ∀ a, StructuralClosure step a (normal a)
  normalInvariantStep : ∀ {a b}, step a b → normal a = normal b
  support : X → Support
  supportInvariantStep : ∀ {a b}, step a b → support a = support b
  schema : X → Schema
  schemaInvariantStep : ∀ {a b}, step a b → schema a = schema b
  output : X → Output
  outputInvariantStep : ∀ {a b}, step a b → output a = output b

namespace QuotientNormalFormPresentation

def related {X : Type u} {Support : Type v} {Schema : Type w} {Output : Type x}
    (P : QuotientNormalFormPresentation X Support Schema Output) (a b : X) : Prop :=
  StructuralClosure P.step a b

theorem normalInvariant {X : Type u} {Support : Type v}
    {Schema : Type w} {Output : Type x}
    (P : QuotientNormalFormPresentation X Support Schema Output)
    {a b : X} (h : P.related a b) : P.normal a = P.normal b := by
  induction h with
  | reflexive a => rfl
  | forward h => exact P.normalInvariantStep h
  | symmetric h ih => exact ih.symm
  | transitive h₁ h₂ ih₁ ih₂ => exact ih₁.trans ih₂

theorem supportInvariant {X : Type u} {Support : Type v}
    {Schema : Type w} {Output : Type x}
    (P : QuotientNormalFormPresentation X Support Schema Output)
    {a b : X} (h : P.related a b) : P.support a = P.support b := by
  induction h with
  | reflexive a => rfl
  | forward h => exact P.supportInvariantStep h
  | symmetric h ih => exact ih.symm
  | transitive h₁ h₂ ih₁ ih₂ => exact ih₁.trans ih₂

theorem schemaInvariant {X : Type u} {Support : Type v}
    {Schema : Type w} {Output : Type x}
    (P : QuotientNormalFormPresentation X Support Schema Output)
    {a b : X} (h : P.related a b) : P.schema a = P.schema b := by
  induction h with
  | reflexive a => rfl
  | forward h => exact P.schemaInvariantStep h
  | symmetric h ih => exact ih.symm
  | transitive h₁ h₂ ih₁ ih₂ => exact ih₁.trans ih₂

theorem outputInvariant {X : Type u} {Support : Type v}
    {Schema : Type w} {Output : Type x}
    (P : QuotientNormalFormPresentation X Support Schema Output)
    {a b : X} (h : P.related a b) : P.output a = P.output b := by
  induction h with
  | reflexive a => rfl
  | forward h => exact P.outputInvariantStep h
  | symmetric h ih => exact ih.symm
  | transitive h₁ h₂ ih₁ ih₂ => exact ih₁.trans ih₂

theorem normalExact {X : Type u} {Support : Type v}
    {Schema : Type w} {Output : Type x}
    (P : QuotientNormalFormPresentation X Support Schema Output) (a b : X) :
    P.normal a = P.normal b ↔ P.related a b := by
  constructor
  · intro h
    exact .transitive (P.reducesToNormal a)
      (.transitive (h ▸ StructuralClosure.reflexive (P.normal a))
        (.symmetric (P.reducesToNormal b)))
  · exact P.normalInvariant

end QuotientNormalFormPresentation

/-- Lean counterpart of “Identity Alignment Preserves Leader Support.” -/
theorem identityAlignmentPreservesLeaderSupport
    {X : Type u} {Support : Type v} {Schema : Type w} {Output : Type x}
    (P : QuotientNormalFormPresentation X Support Schema Output)
    {a b : X} (h : P.related a b) : P.support a = P.support b :=
  P.supportInvariant h

/-- Lean counterpart of “Ambient Quotient-Normal-Form Exactness.” -/
theorem ambientQuotientNormalFormExactness
    {X : Type u} {Support : Type v} {Schema : Type w} {Output : Type x}
    (P : QuotientNormalFormPresentation X Support Schema Output) (a b : X) :
    P.related (P.normal a) a ∧
    (P.normal a = P.normal b ↔ P.related a b) ∧
    P.support (P.normal a) = P.support a ∧
    P.schema (P.normal a) = P.schema a ∧
    P.output (P.normal a) = P.output a ∧
    P.normal (P.normal a) = P.normal a := by
  have hr : P.related a (P.normal a) := P.reducesToNormal a
  refine ⟨.symmetric hr, P.normalExact a b, ?_, ?_, ?_, ?_⟩
  · exact (P.supportInvariant hr).symm
  · exact (P.schemaInvariant hr).symm
  · exact (P.outputInvariant hr).symm
  · exact (P.normalInvariant hr).symm

/-- Canonical shape is normalization of the exact leader kernel; structural
    equivalence remains the closure generated independently by `step`. -/
structure EffectiveShapeSystem (Node : Type u) (Kernel : Type v)
    (Support : Type w) (Output : Type x) where
  kernel : Node → Kernel
  quotient : QuotientNormalFormPresentation Kernel Support Unit Output

def EffectiveShapeSystem.canonicalShape
    {Node : Type u} {Kernel : Type v} {Support : Type w} {Output : Type x}
    (C : EffectiveShapeSystem Node Kernel Support Output) (n : Node) : Kernel :=
  C.quotient.normal (C.kernel n)

def EffectiveShapeSystem.kernelEquivalent
    {Node : Type u} {Kernel : Type v} {Support : Type w} {Output : Type x}
    (C : EffectiveShapeSystem Node Kernel Support Output) (n m : Node) : Prop :=
  C.quotient.related (C.kernel n) (C.kernel m)

/-- Lean counterpart of “Effective-Support Canonical-Shape Exactness.” -/
theorem effectiveSupportCanonicalShapeExactness
    {Node : Type u} {Kernel : Type v} {Support : Type w} {Output : Type x}
    (C : EffectiveShapeSystem Node Kernel Support Output) (n m : Node) :
    C.canonicalShape n = C.canonicalShape m ↔ C.kernelEquivalent n m :=
  C.quotient.normalExact (C.kernel n) (C.kernel m)

/-- A rebuild step is licensed only by a strict decrease of the explicit
    finite-work measure. -/
structure RebuildSystem (State : Type u) where
  dirtyMeasure : State → Nat
  Step : State → State → Prop
  decreases : ∀ {s t}, Step s t → dirtyMeasure t < dirtyMeasure s
  Quiescent : State → Prop
  progress : ∀ s, ¬ Quiescent s → ∃ t, Step s t

/-- Finite reachability by zero or more rebuild steps. -/
inductive RebuildReachable {State : Type u} (R : RebuildSystem State) :
    State → State → Prop where
  | reflexive (s : State) : RebuildReachable R s s
  | step (h : R.Step s t) (rest : RebuildReachable R t q) :
      RebuildReachable R s q

theorem accessibleSubrelation {State : Type u}
    {r s : State → State → Prop}
    (h : ∀ {a b}, s a b → r a b) {a : State} (ha : Acc r a) : Acc s a := by
  induction ha with
  | intro a next ih =>
    exact Acc.intro a (fun b hb => ih b (h hb))

theorem wellFoundedSubrelation {State : Type u}
    {r s : State → State → Prop}
    (h : ∀ {a b}, s a b → r a b) (hr : WellFounded r) : WellFounded s := by
  apply WellFounded.intro
  intro a
  exact accessibleSubrelation h (hr.apply a)

/-- Strict decrease makes the rebuild transition well founded. -/
theorem rebuildStepWellFounded {State : Type u} (R : RebuildSystem State) :
    WellFounded (fun next current => R.Step current next) := by
  apply wellFoundedSubrelation R.decreases
  exact InvImage.wf R.dirtyMeasure Nat.lt_wfRel.wf

/-- Lean counterpart of “Finite Rebuild Quiescence.”  Every initial state
    reaches a quiescent state because every nonquiescent state progresses and
    every progress step strictly decreases the finite-work measure. -/
theorem finiteRebuildQuiescence {State : Type u} (R : RebuildSystem State)
    (initial : State) :
    ∃ final, RebuildReachable R initial final ∧ R.Quiescent final := by
  refine WellFounded.induction (C := fun start =>
    ∃ final, RebuildReachable R start final ∧ R.Quiescent final)
    (rebuildStepWellFounded R) initial ?_
  intro current ih
  by_cases done : R.Quiescent current
  · exact ⟨current, .reflexive current, done⟩
  · rcases R.progress current done with ⟨next, hstep⟩
    rcases ih next hstep with ⟨final, reach, quiet⟩
    exact ⟨final, .step hstep reach, quiet⟩

end TypedSlottedEGraphsPaper
