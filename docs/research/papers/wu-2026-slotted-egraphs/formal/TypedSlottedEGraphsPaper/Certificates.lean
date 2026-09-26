import TypedSlottedEGraphsPaper.StructuralClaims

namespace TypedSlottedEGraphsPaper

universe u v w x y z

/-- An intrinsically typed term language with capture-avoiding transport and
    independently identified primitive and congruence rules. -/
structure TypedTermLanguage (Ty : Type u) where
  Term : TypedSlotContext.{u, v} Ty → Ty → Type w
  rename : {Γ Δ : TypedSlotContext.{u, v} Ty} →
    TypedSlotEmbedding Γ Δ → {τ : Ty} → Term Γ τ → Term Δ τ
  renameId : ∀ {Γ τ} (t : Term Γ τ),
    rename (TypedSlotEmbedding.id Γ) t = t
  renameComp : ∀ {Γ Δ Ξ τ} (e : TypedSlotEmbedding Δ Ξ)
    (m : TypedSlotEmbedding Γ Δ) (t : Term Γ τ),
    rename e (rename m t) = rename (TypedSlotEmbedding.comp e m) t
  PrimitiveEquation : {Γ : TypedSlotContext.{u, v} Ty} → {τ : Ty} →
    Term Γ τ → Term Γ τ → Prop
  StructuralCongruence : {Γ : TypedSlotContext.{u, v} Ty} → {τ : Ty} →
    Term Γ τ → Term Γ τ → Prop

/-- Typed equational certificates are finite derivation trees.  Their leaves
    are only declared equations or forward structural-congruence rules. -/
inductive TypedEquationalCertificate {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty) :
    {Γ : TypedSlotContext.{u, v} Ty} → {τ : Ty} →
    L.Term Γ τ → L.Term Γ τ → Prop where
  | reflexive (t : L.Term Γ τ) : TypedEquationalCertificate L t t
  | primitive (h : L.PrimitiveEquation t s) :
      TypedEquationalCertificate L t s
  | congruence (h : L.StructuralCongruence t s) :
      TypedEquationalCertificate L t s
  | symmetric (d : TypedEquationalCertificate L t s) :
      TypedEquationalCertificate L s t
  | transitive (d₁ : TypedEquationalCertificate L t s)
      (d₂ : TypedEquationalCertificate L s r) :
      TypedEquationalCertificate L t r
  | transport (e : TypedSlotEmbedding Γ Δ)
      (d : TypedEquationalCertificate L t s) :
      TypedEquationalCertificate L (L.rename e t) (L.rename e s)

namespace TypedEquationalCertificate

theorem rewriteRight {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty} {t s r : L.Term Γ τ}
    (d : TypedEquationalCertificate L t s) (h : s = r) :
    TypedEquationalCertificate L t r := by
  cases h
  exact d

theorem rewriteLeft {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty} {t s r : L.Term Γ τ}
    (h : r = t) (d : TypedEquationalCertificate L t s) :
    TypedEquationalCertificate L r s := by
  cases h
  exact d

end TypedEquationalCertificate

/-- A model interprets primitive equations, congruence rules, and renaming.
    These local obligations are sufficient to validate any finite certificate. -/
structure TypedModel {Ty : Type u} (L : TypedTermLanguage.{u, v, w} Ty) where
  Value : Ty → Type x
  Environment : TypedSlotContext.{u, v} Ty → Type y
  restrict : {Γ Δ : TypedSlotContext.{u, v} Ty} →
    TypedSlotEmbedding Γ Δ → Environment Δ → Environment Γ
  evaluate : {Γ : TypedSlotContext.{u, v} Ty} → {τ : Ty} →
    L.Term Γ τ → Environment Γ → Value τ
  renameEvaluation : ∀ {Γ Δ τ} (e : TypedSlotEmbedding Γ Δ)
    (t : L.Term Γ τ) (η : Environment Δ),
    evaluate (L.rename e t) η = evaluate t (restrict e η)
  primitiveSound : ∀ {Γ τ} {t s : L.Term Γ τ},
    L.PrimitiveEquation t s → ∀ η, evaluate t η = evaluate s η
  congruenceSound : ∀ {Γ τ} {t s : L.Term Γ τ},
    L.StructuralCongruence t s → ∀ η, evaluate t η = evaluate s η

theorem typedCertificateSemanticSoundness
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    (M : TypedModel.{u, v, w, x, y} L)
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {t s : L.Term Γ τ} (d : TypedEquationalCertificate L t s) :
    ∀ η : M.Environment Γ, M.evaluate t η = M.evaluate s η := by
  induction d with
  | reflexive t => intro η; rfl
  | primitive h => exact M.primitiveSound h
  | congruence h => exact M.congruenceSound h
  | symmetric d ih => intro η; exact (ih η).symm
  | transitive d₁ d₂ ih₁ ih₂ => intro η; exact (ih₁ η).trans (ih₂ η)
  | transport e d ih =>
      intro η
      rw [M.renameEvaluation, M.renameEvaluation]
      exact ih (M.restrict e η)

/-- A proof-relevant alpha derivation.  Binder-block steps must carry the
    independently checked equation supplied by the descriptor. -/
inductive CertifiedAlphaDerivation {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty} :
    L.Term Γ τ → L.Term Γ τ → Prop where
  | reflexive (t : L.Term Γ τ) : CertifiedAlphaDerivation L t t
  | ordinary (d : TypedEquationalCertificate L t s) :
      CertifiedAlphaDerivation L t s
  | binderBlock (descriptorLaw : TypedEquationalCertificate L t s) :
      CertifiedAlphaDerivation L t s
  | symmetric (d : CertifiedAlphaDerivation L t s) :
      CertifiedAlphaDerivation L s t
  | transitive (d₁ : CertifiedAlphaDerivation L t s)
      (d₂ : CertifiedAlphaDerivation L s r) :
      CertifiedAlphaDerivation L t r

/-- Lean counterpart of “Soundness of Typed Alpha-Equivalence Modulo
    Binder-Block Automorphisms.” -/
theorem soundnessOfTypedAlphaEquivalenceModuloBinderBlockAutomorphisms
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {t s : L.Term Γ τ} (d : CertifiedAlphaDerivation L t s) :
    TypedEquationalCertificate L t s := by
  induction d with
  | reflexive t => exact .reflexive t
  | ordinary d => exact d
  | binderBlock d => exact d
  | symmetric d ih => exact .symmetric ih
  | transitive d₁ d₂ ih₁ ih₂ => exact .transitive ih₁ ih₂

/-- A node paired with its declared source realization. -/
structure RealizedNode {Ty : Type u} (L : TypedTermLanguage.{u, v, w} Ty)
    (Γ : TypedSlotContext.{u, v} Ty) (τ : Ty) where
  syntaxCode : Nat
  realization : L.Term Γ τ

namespace RealizedNode

def transport {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ Δ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    (e : TypedSlotEmbedding Γ Δ) (n : RealizedNode L Γ τ) :
    RealizedNode L Δ τ where
  syntaxCode := n.syntaxCode
  realization := L.rename e n.realization

end RealizedNode

/-- Lean counterpart of “Naturality of Structural Realization.” -/
theorem naturalityOfStructuralRealization
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ Δ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    (e : TypedSlotEmbedding Γ Δ) (n : RealizedNode L Γ τ) :
    (RealizedNode.transport e n).realization = L.rename e n.realization :=
  rfl

/-- Structural congruence is a finite tree whose leaves are already certified
    and whose internal nodes are checked forward-congruence steps. -/
inductive PortNodeCongruenceDerivation {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty} :
    L.Term Γ τ → L.Term Γ τ → Prop where
  | leaf (d : TypedEquationalCertificate L t s) :
      PortNodeCongruenceDerivation L t s
  | node (h : L.StructuralCongruence t s) :
      PortNodeCongruenceDerivation L t s
  | symmetric (d : PortNodeCongruenceDerivation L t s) :
      PortNodeCongruenceDerivation L s t
  | transitive (d₁ : PortNodeCongruenceDerivation L t s)
      (d₂ : PortNodeCongruenceDerivation L s r) :
      PortNodeCongruenceDerivation L t r

/-- Lean counterpart of “Soundness of Port and Node Congruence.” -/
theorem soundnessOfPortAndNodeCongruence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {t s : L.Term Γ τ} (d : PortNodeCongruenceDerivation L t s) :
    TypedEquationalCertificate L t s := by
  induction d with
  | leaf d => exact d
  | node h => exact .congruence h
  | symmetric d ih => exact .symmetric ih
  | transitive d₁ d₂ ih₁ ih₂ => exact .transitive ih₁ ih₂

/-- The witness term associated with every typed e-class identifier. -/
structure TypedWitnessFamily {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty) where
  ClassId : Ty → Type x
  interface : {τ : Ty} → ClassId τ → TypedSlotContext.{u, v} Ty
  witness : {τ : Ty} → (a : ClassId τ) → L.Term (interface a) τ

/-- Endpoint families for the three coherence obligations EC, PC, and SC. -/
structure CoherenceProblem {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty) where
  StoredCase : (Γ : TypedSlotContext.{u, v} Ty) → (τ : Ty) → Type x
  storedLeft : {Γ : TypedSlotContext.{u, v} Ty} → {τ : Ty} →
    StoredCase Γ τ → L.Term Γ τ
  storedRight : {Γ : TypedSlotContext.{u, v} Ty} → {τ : Ty} →
    StoredCase Γ τ → L.Term Γ τ
  ParentCase : (Γ : TypedSlotContext.{u, v} Ty) → (τ : Ty) → Type y
  parentLeft : {Γ : TypedSlotContext.{u, v} Ty} → {τ : Ty} →
    ParentCase Γ τ → L.Term Γ τ
  parentRight : {Γ : TypedSlotContext.{u, v} Ty} → {τ : Ty} →
    ParentCase Γ τ → L.Term Γ τ
  SymmetryCase : (Γ : TypedSlotContext.{u, v} Ty) → (τ : Ty) → Type z
  symmetryLeft : {Γ : TypedSlotContext.{u, v} Ty} → {τ : Ty} →
    SymmetryCase Γ τ → L.Term Γ τ
  symmetryRight : {Γ : TypedSlotContext.{u, v} Ty} → {τ : Ty} →
    SymmetryCase Γ τ → L.Term Γ τ

/-- Lean counterpart of “Coherent Equational Certificate Family.” -/
structure CoherentEquationalCertificateFamily {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (P : CoherenceProblem.{u, v, w, x, y, z} L) : Prop where
  storedCertificate : ∀ {Γ τ} (c : P.StoredCase Γ τ),
    TypedEquationalCertificate L (P.storedLeft c) (P.storedRight c)
  parentCertificate : ∀ {Γ τ} (c : P.ParentCase Γ τ),
    TypedEquationalCertificate L (P.parentLeft c) (P.parentRight c)
  symmetryCertificate : ∀ {Γ τ} (c : P.SymmetryCase Γ τ),
    TypedEquationalCertificate L (P.symmetryLeft c) (P.symmetryRight c)

end TypedSlottedEGraphsPaper
