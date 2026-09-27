import TypedSlottedEGraphsPaper.Replay

namespace TypedSlottedEGraphsPaper

universe u v w x y z

/-- The nine transition families from the headline theorem.  Every evidence
    object is local to one step; the corresponding preservation field checks
    that this local evidence extends the coherent certificate family. -/
structure CertifiedTransitionSemantics {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty) (State : Type x) where
  problem : State → CoherenceProblem.{u, v, w, y, y, y} L
  Empty : State → Prop
  emptyCoherent : ∀ {s}, Empty s →
    CoherentEquationalCertificateFamily (problem s)
  InsertionEvidence : State → State → Type z
  insertionPreserves : ∀ {s t}, InsertionEvidence s t →
    CoherentEquationalCertificateFamily (problem s) →
    CoherentEquationalCertificateFamily (problem t)
  CanonicalizationEvidence : State → State → Type z
  canonicalizationPreserves : ∀ {s t}, CanonicalizationEvidence s t →
    CoherentEquationalCertificateFamily (problem s) →
    CoherentEquationalCertificateFamily (problem t)
  CollisionEvidence : State → State → Type z
  collisionPreserves : ∀ {s t}, CollisionEvidence s t →
    CoherentEquationalCertificateFamily (problem s) →
    CoherentEquationalCertificateFamily (problem t)
  UnionEvidence : State → State → Type z
  unionPreserves : ∀ {s t}, UnionEvidence s t →
    CoherentEquationalCertificateFamily (problem s) →
    CoherentEquationalCertificateFamily (problem t)
  SymmetryEvidence : State → State → Type z
  symmetryPreserves : ∀ {s t}, SymmetryEvidence s t →
    CoherentEquationalCertificateFamily (problem s) →
    CoherentEquationalCertificateFamily (problem t)
  InterfaceRestrictionEvidence : State → State → Type z
  interfaceRestrictionPreserves : ∀ {s t}, InterfaceRestrictionEvidence s t →
    CoherentEquationalCertificateFamily (problem s) →
    CoherentEquationalCertificateFamily (problem t)
  NoninferentialUnionEvidence : State → State → Type z
  noninferentialUnionPreserves : ∀ {s t}, NoninferentialUnionEvidence s t →
    CoherentEquationalCertificateFamily (problem s) →
    CoherentEquationalCertificateFamily (problem t)
  RebuildEvidence : State → State → Type z
  rebuildPreserves : ∀ {s t}, RebuildEvidence s t →
    CoherentEquationalCertificateFamily (problem s) →
    CoherentEquationalCertificateFamily (problem t)
  PathCompressionEvidence : State → State → Type z
  pathCompressionPreserves : ∀ {s t}, PathCompressionEvidence s t →
    CoherentEquationalCertificateFamily (problem s) →
    CoherentEquationalCertificateFamily (problem t)

/-- One proof-relevant certified transition. -/
inductive CertifiedStep {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {State : Type x} (S : CertifiedTransitionSemantics.{u, v, w, x, y, z} L State) :
    State → State → Type (max u v w x y z) where
  | insertion (e : S.InsertionEvidence s t) : CertifiedStep S s t
  | canonicalization (e : S.CanonicalizationEvidence s t) : CertifiedStep S s t
  | collision (e : S.CollisionEvidence s t) : CertifiedStep S s t
  | union (e : S.UnionEvidence s t) : CertifiedStep S s t
  | symmetry (e : S.SymmetryEvidence s t) : CertifiedStep S s t
  | interfaceRestriction (e : S.InterfaceRestrictionEvidence s t) :
      CertifiedStep S s t
  | noninferentialUnion (e : S.NoninferentialUnionEvidence s t) :
      CertifiedStep S s t
  | rebuild (e : S.RebuildEvidence s t) : CertifiedStep S s t
  | pathCompression (e : S.PathCompressionEvidence s t) : CertifiedStep S s t

/-- A finite trace of certified transitions. -/
inductive CertifiedTrace {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {State : Type x} (S : CertifiedTransitionSemantics.{u, v, w, x, y, z} L State) :
    State → State → Type (max u v w x y z) where
  | reflexive (s : State) : CertifiedTrace S s s
  | step (head : CertifiedStep S s t) (tail : CertifiedTrace S t q) :
      CertifiedTrace S s q

theorem certifiedStepPreservesCoherence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {State : Type x}
    {S : CertifiedTransitionSemantics.{u, v, w, x, y, z} L State}
    {s t : State} (step : CertifiedStep S s t)
    (coherent : CoherentEquationalCertificateFamily (S.problem s)) :
    CoherentEquationalCertificateFamily (S.problem t) := by
  cases step with
  | insertion e => exact S.insertionPreserves e coherent
  | canonicalization e => exact S.canonicalizationPreserves e coherent
  | collision e => exact S.collisionPreserves e coherent
  | union e => exact S.unionPreserves e coherent
  | symmetry e => exact S.symmetryPreserves e coherent
  | interfaceRestriction e => exact S.interfaceRestrictionPreserves e coherent
  | noninferentialUnion e => exact S.noninferentialUnionPreserves e coherent
  | rebuild e => exact S.rebuildPreserves e coherent
  | pathCompression e => exact S.pathCompressionPreserves e coherent

theorem certifiedTracePreservesCoherence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {State : Type x}
    {S : CertifiedTransitionSemantics.{u, v, w, x, y, z} L State}
    {s t : State} (trace : CertifiedTrace S s t)
    (coherent : CoherentEquationalCertificateFamily (S.problem s)) :
    CoherentEquationalCertificateFamily (S.problem t) := by
  induction trace with
  | reflexive s => exact coherent
  | step head tail ih => exact ih (certifiedStepPreservesCoherence head coherent)

/-- Lean counterpart of “Certificate-Preserving Reachability and
    Finite-Unfolding Soundness.”  The result is conditional on finite
    unfolding certificates and the checked same-leader alignment certificate. -/
theorem certificatePreservingReachabilityAndFiniteUnfoldingSoundness
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {State : Type x}
    (S : CertifiedTransitionSemantics.{u, v, w, x, y, z} L State)
    {initial final : State} (empty : S.Empty initial)
    (trace : CertifiedTrace S initial final)
    {W : TypedWitnessFamily.{u, v, w, x} L} {τ : Ty}
    {leftClass rightClass leader : W.ClassId τ}
    (leftPath : CertifiedParentPath W leftClass leader)
    (rightPath : CertifiedParentPath W rightClass leader)
    {Γ : TypedSlotContext.{u, v} Ty}
    (leftCaller : TypedSlotEmbedding (W.interface leftClass) Γ)
    (rightCaller : TypedSlotEmbedding (W.interface rightClass) Γ)
    {leftTerm rightTerm : L.Term Γ τ}
    (leftRep : FiniteRepresentation L
      (L.rename leftCaller (W.witness leftClass)) leftTerm)
    (rightRep : FiniteRepresentation L
      (L.rename rightCaller (W.witness rightClass)) rightTerm)
    (leaderAlignment : TypedEquationalCertificate L
      (L.rename (TypedSlotEmbedding.comp leftCaller leftPath.embedding)
        (W.witness leader))
      (L.rename (TypedSlotEmbedding.comp rightCaller rightPath.embedding)
        (W.witness leader)))
    (M : TypedModel.{u, v, w, x, y} L) (η : M.Environment Γ) :
    CoherentEquationalCertificateFamily (S.problem final) ∧
    TypedEquationalCertificate L leftTerm rightTerm ∧
    M.evaluate leftTerm η = M.evaluate rightTerm η := by
  have finalCoherent := certifiedTracePreservesCoherence trace
    (S.emptyCoherent empty)
  have leftCert :=
    (findAndFiniteUnfoldingPreserveEquationalCertificates
      leftPath leftCaller leftRep).2
  have rightCert :=
    (findAndFiniteUnfoldingPreserveEquationalCertificates
      rightPath rightCaller rightRep).2
  let resultCert := TypedEquationalCertificate.transitive leftCert
    (TypedEquationalCertificate.transitive leaderAlignment
      (TypedEquationalCertificate.symmetric rightCert))
  exact ⟨finalCoherent, resultCert,
    typedCertificateSemanticSoundness M resultCert η⟩

end TypedSlottedEGraphsPaper
