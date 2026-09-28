import TypedSlottedEGraphsPaper.Certificates

namespace TypedSlottedEGraphsPaper

universe u v w x

/-- A parent edge carries both its typed embedding and the equation that
    licenses following it. -/
structure CertifiedParentEdge {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (W : TypedWitnessFamily.{u, v, w, x} L) {τ : Ty}
    (child parent : W.ClassId τ) where
  embedding : TypedSlotEmbedding (W.interface parent) (W.interface child)
  certificate : TypedEquationalCertificate L (W.witness child)
    (L.rename embedding (W.witness parent))

/-- A finite parent path composes only certified edges. -/
inductive CertifiedParentPath {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (W : TypedWitnessFamily.{u, v, w, x} L) {τ : Ty} :
    W.ClassId τ → W.ClassId τ → Type (max u v w x) where
  | reflexive (a : W.ClassId τ) : CertifiedParentPath W a a
  | step (edge : CertifiedParentEdge W child parent)
      (rest : CertifiedParentPath W parent leader) :
      CertifiedParentPath W child leader

namespace CertifiedParentPath

def embedding {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L} {τ : Ty}
    {child leader : W.ClassId τ} (path : CertifiedParentPath W child leader) :
    TypedSlotEmbedding (W.interface leader) (W.interface child) :=
  match path with
  | .reflexive a => TypedSlotEmbedding.id (W.interface a)
  | .step edge rest => TypedSlotEmbedding.comp edge.embedding (embedding rest)

theorem certificate {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L} {τ : Ty}
    {child leader : W.ClassId τ} (path : CertifiedParentPath W child leader) :
    TypedEquationalCertificate L (W.witness child)
      (L.rename path.embedding (W.witness leader)) := by
  induction path with
  | reflexive a =>
      exact (TypedEquationalCertificate.reflexive (W.witness a)).rewriteRight
        (L.renameId (W.witness a)).symm
  | step edge rest ih =>
      apply TypedEquationalCertificate.rewriteRight
        (.transitive edge.certificate (.transport edge.embedding ih))
      exact L.renameComp edge.embedding rest.embedding (W.witness _)

theorem callerCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L} {τ : Ty}
    {child leader : W.ClassId τ} (path : CertifiedParentPath W child leader)
    {Γ : TypedSlotContext.{u, v} Ty}
    (caller : TypedSlotEmbedding (W.interface child) Γ) :
    TypedEquationalCertificate L (L.rename caller (W.witness child))
      (L.rename (TypedSlotEmbedding.comp caller path.embedding)
        (W.witness leader)) := by
  apply TypedEquationalCertificate.rewriteRight
    (.transport caller path.certificate)
  exact L.renameComp caller path.embedding (W.witness leader)

end CertifiedParentPath

/-- A finite unfolding is a finite sequence of locally checked expansion
    equations ending at its witness endpoint. -/
inductive FiniteRepresentation {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    (endpoint : L.Term Γ τ) : L.Term Γ τ → Prop where
  | endpoint : FiniteRepresentation L endpoint endpoint
  | expand (edgeCert : TypedEquationalCertificate L term next)
      (rest : FiniteRepresentation L endpoint next) :
      FiniteRepresentation L endpoint term

theorem finiteRepresentationCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {endpoint term : L.Term Γ τ}
    (rep : FiniteRepresentation L endpoint term) :
    TypedEquationalCertificate L term endpoint := by
  induction rep with
  | endpoint => exact .reflexive endpoint
  | expand edgeCert rest ih => exact .transitive edgeCert ih

/-- Lean counterpart of “Find and Finite Unfolding Preserve Equational
    Certificates.” -/
theorem findAndFiniteUnfoldingPreserveEquationalCertificates
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L} {τ : Ty}
    {child leader : W.ClassId τ} (path : CertifiedParentPath W child leader)
    {Γ : TypedSlotContext.{u, v} Ty}
    (caller : TypedSlotEmbedding (W.interface child) Γ)
    {term : L.Term Γ τ}
    (rep : FiniteRepresentation L (L.rename caller (W.witness child)) term) :
    TypedEquationalCertificate L (L.rename caller (W.witness child))
      (L.rename (TypedSlotEmbedding.comp caller path.embedding)
        (W.witness leader)) ∧
    TypedEquationalCertificate L term
      (L.rename (TypedSlotEmbedding.comp caller path.embedding)
        (W.witness leader)) := by
  let findCert := path.callerCertificate caller
  exact ⟨findCert, .transitive (finiteRepresentationCertificate rep) findCert⟩

/-- The retained kernel provenance is an independent structural derivation
    from the source realization to the transported exact kernel. -/
structure CertifiedKernelExtraction {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    (Γ Δ : TypedSlotContext.{u, v} Ty) (τ : Ty) where
  original : L.Term Γ τ
  kernel : L.Term Δ τ
  inclusion : TypedSlotEmbedding Δ Γ
  provenance : PortNodeCongruenceDerivation L original
    (L.rename inclusion kernel)

/-- Lean counterpart of “Certified Leader-Kernel Extraction.” -/
theorem certifiedLeaderKernelExtraction
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ Δ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    (K : CertifiedKernelExtraction L Γ Δ τ) :
    TypedEquationalCertificate L K.original (L.rename K.inclusion K.kernel) :=
  soundnessOfPortAndNodeCongruence K.provenance

/-- Lean counterpart of “Certified Effective-Shape Collision.”  Compatibility
    is stated at the typed embedding level; endpoint equalities are derived
    using the language's renaming-composition law. -/
theorem certifiedEffectiveShapeCollision
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ₁ Γ₂ Δ₁ Δ₂ Ω : TypedSlotContext.{u, v} Ty} {τ : Ty}
    (K₁ : CertifiedKernelExtraction L Γ₁ Δ₁ τ)
    (K₂ : CertifiedKernelExtraction L Γ₂ Δ₂ τ)
    (ρ : TypedSlotRenaming Δ₁ Δ₂)
    (alignment : PortNodeCongruenceDerivation L
      (L.rename ρ.toTypedSlotEmbedding K₁.kernel) K₂.kernel)
    (e₁ : TypedSlotEmbedding Γ₁ Ω) (e₂ : TypedSlotEmbedding Γ₂ Ω)
    (compatible : TypedSlotEmbedding.comp e₁ K₁.inclusion =
      TypedSlotEmbedding.comp e₂
        (TypedSlotEmbedding.comp K₂.inclusion ρ.toTypedSlotEmbedding)) :
    TypedEquationalCertificate L (L.rename e₁ K₁.original)
      (L.rename e₂ K₂.original) := by
  let d₁ := TypedEquationalCertificate.transport e₁
    (certifiedLeaderKernelExtraction K₁)
  let bridge := TypedEquationalCertificate.transport
    (TypedSlotEmbedding.comp e₂ K₂.inclusion)
    (soundnessOfPortAndNodeCongruence alignment)
  let d₂ := TypedEquationalCertificate.transport e₂
    (certifiedLeaderKernelExtraction K₂)
  have h₁ : L.rename e₁ (L.rename K₁.inclusion K₁.kernel) =
      L.rename (TypedSlotEmbedding.comp e₁ K₁.inclusion) K₁.kernel :=
    L.renameComp e₁ K₁.inclusion K₁.kernel
  have hbLeft :
      L.rename (TypedSlotEmbedding.comp e₂ K₂.inclusion)
        (L.rename ρ.toTypedSlotEmbedding K₁.kernel) =
      L.rename (TypedSlotEmbedding.comp e₁ K₁.inclusion) K₁.kernel := by
    rw [L.renameComp]
    apply congrArg (fun emb => L.rename emb K₁.kernel)
    exact (TypedSlotEmbedding.comp_assoc e₂ K₂.inclusion
      ρ.toTypedSlotEmbedding).trans compatible.symm
  have hbRight :
      L.rename (TypedSlotEmbedding.comp e₂ K₂.inclusion) K₂.kernel =
      L.rename e₂ (L.rename K₂.inclusion K₂.kernel) := by
    exact (L.renameComp e₂ K₂.inclusion K₂.kernel).symm
  exact .transitive (d₁.rewriteRight h₁)
    (.transitive (bridge.rewriteLeft hbLeft.symm |>.rewriteRight hbRight)
      (.symmetric d₂))

end TypedSlottedEGraphsPaper
