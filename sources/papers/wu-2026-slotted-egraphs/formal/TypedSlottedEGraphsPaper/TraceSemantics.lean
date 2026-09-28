import TypedSlottedEGraphsPaper.Replay

namespace TypedSlottedEGraphsPaper

universe u v w x y z

/-- The dependent index of one live theorem obligation. -/
structure TypedEndpointIndex (Ty : Type u) where
  context : TypedSlotContext.{u, v} Ty
  output : Ty

/-- Transport a term along equality of its dependent context/output index. -/
def castEndpointTerm {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {i j : TypedEndpointIndex.{u, v} Ty} (h : i = j)
    (term : L.Term i.context i.output) : L.Term j.context j.output := by
  cases h
  exact term

/-- Equality transport preserves a finite equational derivation. -/
theorem castTypedEquationalCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {i j : TypedEndpointIndex.{u, v} Ty} (h : i = j)
    {left right : L.Term i.context i.output}
    (certificate : TypedEquationalCertificate L left right) :
    TypedEquationalCertificate L (castEndpointTerm h left)
      (castEndpointTerm h right) := by
  cases h
  exact certificate

/-- A live theorem obligation packages its own context and output type with
    its explicitly typed pair of endpoints. -/
structure TypedEndpointPair {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty) where
  index : TypedEndpointIndex.{u, v} Ty
  left : L.Term index.context index.output
  right : L.Term index.context index.output

/-- Exact equality of packaged obligations transports their certificate. -/
theorem certificateOfEndpointPairEquality {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {p q : TypedEndpointPair L} (h : p = q)
    (certificate : TypedEquationalCertificate L p.left p.right) :
    TypedEquationalCertificate L q.left q.right := by
  cases h
  exact certificate

/-- The theorem-facing part of a graph state: precisely the currently live
    endpoint obligations.  No certificate is stored in the state. -/
structure TheoremTraceState {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty) where
  Obligation : Type x
  endpoints : Obligation → TypedEndpointPair L

/-- Coherence means that every live obligation has a derivation.  It is a
    derived predicate, rather than a transition-system field. -/
def TheoremTraceState.Coherent {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (s : TheoremTraceState.{u, v, w, x} L) : Prop :=
  ∀ o : s.Obligation,
    TypedEquationalCertificate L (s.endpoints o).left (s.endpoints o).right

/-- An inherited target obligation names its source and states the endpoint
    equalities introduced by a storage-only transformation. -/
structure InheritedObligation {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (s t : TheoremTraceState.{u, v, w, x} L)
    (target : t.Obligation) where
  source : s.Obligation
  pair_eq : s.endpoints source = t.endpoints target

namespace InheritedObligation

theorem certificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {s t : TheoremTraceState.{u, v, w, x} L}
    {target : t.Obligation} (h : InheritedObligation s t target)
    (coherent : s.Coherent) :
    TypedEquationalCertificate L (t.endpoints target).left
      (t.endpoints target).right := by
  exact certificateOfEndpointPairEquality h.pair_eq (coherent h.source)

end InheritedObligation

/-- The proof-relevant classification of one target obligation after an
    addition. -/
inductive AddedObligationCase {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (s t : TheoremTraceState.{u, v, w, x} L)
    (target : t.Obligation) where
  | inherited (entry : InheritedObligation s t target) :
      AddedObligationCase s t target
  | added (certificate : TypedEquationalCertificate L
      (t.endpoints target).left (t.endpoints target).right) :
      AddedObligationCase s t target

/-- Addition evidence classifies every target obligation as either inherited
    or newly justified by one local certificate. -/
structure ObligationAddition {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (s t : TheoremTraceState.{u, v, w, x} L) where
  classify : (target : t.Obligation) → AddedObligationCase s t target

/-- Rekey evidence transports a source obligation through independently
    checked left and right endpoint bridges. -/
structure RekeyedObligation {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (s t : TheoremTraceState.{u, v, w, x} L)
    (target : t.Obligation) where
  source : s.Obligation
  index_eq : (s.endpoints source).index = (t.endpoints target).index
  leftBridge : TypedEquationalCertificate L (t.endpoints target).left
    (castEndpointTerm index_eq (s.endpoints source).left)
  rightBridge : TypedEquationalCertificate L
    (castEndpointTerm index_eq (s.endpoints source).right)
    (t.endpoints target).right

/-- A rekey transformation gives local bridges for each target obligation. -/
structure ObligationRekey {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (s t : TheoremTraceState.{u, v, w, x} L) where
  rekey : (target : t.Obligation) → RekeyedObligation s t target

/-- Removal evidence is only a target-to-source obligation map with endpoint
    equalities.  It cannot manufacture a certificate. -/
structure ObligationRemoval {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (s t : TheoremTraceState.{u, v, w, x} L) where
  retain : (target : t.Obligation) → InheritedObligation s t target

/-- Composition evidence obtains a target certificate by composing two source
    obligations with three local endpoint bridges. -/
structure ComposedObligation {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (s t : TheoremTraceState.{u, v, w, x} L)
    (target : t.Obligation) where
  first : s.Obligation
  second : s.Obligation
  firstIndex_eq : (s.endpoints first).index = (t.endpoints target).index
  secondIndex_eq : (s.endpoints second).index = (t.endpoints target).index
  leftBridge : TypedEquationalCertificate L (t.endpoints target).left
    (castEndpointTerm firstIndex_eq (s.endpoints first).left)
  middleBridge : TypedEquationalCertificate L
    (castEndpointTerm firstIndex_eq (s.endpoints first).right)
    (castEndpointTerm secondIndex_eq (s.endpoints second).left)
  rightBridge : TypedEquationalCertificate L
    (castEndpointTerm secondIndex_eq (s.endpoints second).right)
    (t.endpoints target).right

/-- A composition transformation supplies one local composition recipe for
    every target obligation. -/
structure ObligationComposition {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (s t : TheoremTraceState.{u, v, w, x} L) where
  compose : (target : t.Obligation) → ComposedObligation s t target

theorem obligationAdditionPreservesCoherence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {s t : TheoremTraceState.{u, v, w, x} L}
    (change : ObligationAddition s t) (coherent : s.Coherent) :
    t.Coherent := by
  intro target
  cases change.classify target with
  | inherited entry => exact entry.certificate coherent
  | added localCertificate => exact localCertificate

theorem obligationRekeyPreservesCoherence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {s t : TheoremTraceState.{u, v, w, x} L}
    (change : ObligationRekey s t) (coherent : s.Coherent) :
    t.Coherent := by
  intro target
  let r := change.rekey target
  have sourceCertificate := castTypedEquationalCertificate r.index_eq
    (coherent r.source)
  exact .transitive r.leftBridge
    (.transitive sourceCertificate r.rightBridge)

theorem obligationRemovalPreservesCoherence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {s t : TheoremTraceState.{u, v, w, x} L}
    (change : ObligationRemoval s t) (coherent : s.Coherent) :
    t.Coherent := by
  intro target
  exact (change.retain target).certificate coherent

theorem obligationCompositionPreservesCoherence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {s t : TheoremTraceState.{u, v, w, x} L}
    (change : ObligationComposition s t) (coherent : s.Coherent) :
    t.Coherent := by
  intro target
  let c := change.compose target
  have firstCertificate := castTypedEquationalCertificate c.firstIndex_eq
    (coherent c.first)
  have secondCertificate := castTypedEquationalCertificate c.secondIndex_eq
    (coherent c.second)
  exact .transitive c.leftBridge
    (.transitive firstCertificate
      (.transitive c.middleBridge
        (.transitive secondCertificate c.rightBridge)))

/-- The nine paper transition families, expressed only through local addition,
    rekey, removal, or composition evidence. -/
inductive LocalCertifiedStep {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty} :
    TheoremTraceState.{u, v, w, x} L →
    TheoremTraceState.{u, v, w, x} L →
    Type (max (u + 2) (v + 2) (w + 2) (x + 2)) where
  | insertion (change : ObligationAddition s t) : LocalCertifiedStep s t
  | canonicalization (change : ObligationRekey s t) : LocalCertifiedStep s t
  | collision (change : ObligationComposition s t) : LocalCertifiedStep s t
  | union (change : ObligationComposition s t) : LocalCertifiedStep s t
  | symmetry (change : ObligationRekey s t) : LocalCertifiedStep s t
  | interfaceRestriction (change : ObligationRekey s t) :
      LocalCertifiedStep s t
  | noninferentialUnion (change : ObligationRemoval s t) :
      LocalCertifiedStep s t
  | rebuild (change : ObligationAddition s t) : LocalCertifiedStep s t
  | pathCompression (change : ObligationComposition s t) :
      LocalCertifiedStep s t

/-- Step preservation is derived from local transition evidence; it is not a
    field stored in a semantics record. -/
theorem localCertifiedStepPreservesCoherence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {s t : TheoremTraceState.{u, v, w, x} L}
    (step : LocalCertifiedStep s t) (coherent : s.Coherent) : t.Coherent := by
  cases step with
  | insertion change =>
      exact obligationAdditionPreservesCoherence change coherent
  | canonicalization change =>
      exact obligationRekeyPreservesCoherence change coherent
  | collision change =>
      exact obligationCompositionPreservesCoherence change coherent
  | union change =>
      exact obligationCompositionPreservesCoherence change coherent
  | symmetry change =>
      exact obligationRekeyPreservesCoherence change coherent
  | interfaceRestriction change =>
      exact obligationRekeyPreservesCoherence change coherent
  | noninferentialUnion change =>
      exact obligationRemovalPreservesCoherence change coherent
  | rebuild change =>
      exact obligationAdditionPreservesCoherence change coherent
  | pathCompression change =>
      exact obligationCompositionPreservesCoherence change coherent

/-- A finite, proof-relevant trace of local certified steps. -/
inductive LocalCertifiedTrace {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty} :
    TheoremTraceState.{u, v, w, x} L →
    TheoremTraceState.{u, v, w, x} L →
    Type (max (u + 2) (v + 2) (w + 2) (x + 2)) where
  | reflexive (s) : LocalCertifiedTrace s s
  | step (head : LocalCertifiedStep s t) (tail : LocalCertifiedTrace t q) :
      LocalCertifiedTrace s q

/-- Trace preservation follows by induction over proof-relevant steps. -/
theorem localCertifiedTracePreservesCoherence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {s t : TheoremTraceState.{u, v, w, x} L}
    (trace : LocalCertifiedTrace s t) (coherent : s.Coherent) :
    t.Coherent := by
  induction trace with
  | reflexive s => exact coherent
  | step head tail ih =>
      exact ih (localCertifiedStepPreservesCoherence head coherent)

/-- A state with no live obligations is coherent by elimination, without an
    `emptyCoherent` field. -/
theorem obligationFreeStateIsCoherent
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {s : TheoremTraceState.{u, v, w, x} L}
    (empty : s.Obligation → False) : s.Coherent := by
  intro target
  exact False.elim (empty target)

/-- Same-leader evidence identifies a checked symmetry of the leader witness
    and proves that its embedding is the left caller's embedding.  The aligned
    leader equation is deliberately not a field. -/
structure SameLeaderSymmetryEvidence {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    (W : TypedWitnessFamily.{u, v, w, x} L) {τ : Ty}
    (leader : W.ClassId τ) (Γ : TypedSlotContext.{u, v} Ty)
    (leftEmbedding rightEmbedding :
      TypedSlotEmbedding (W.interface leader) Γ) where
  symmetry : TypedSlotRenaming (W.interface leader) (W.interface leader)
  symmetryCertificate : TypedEquationalCertificate L (W.witness leader)
    (L.rename symmetry.toTypedSlotEmbedding (W.witness leader))
  embeddingCompatibility : leftEmbedding = TypedSlotEmbedding.comp
    rightEmbedding symmetry.toTypedSlotEmbedding

/-- The aligned leader certificate is derived by transporting the checked SC
    certificate and rewriting only by embedding compatibility. -/
theorem alignedLeaderCertificateOfSameLeaderSymmetry
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L} {τ : Ty}
    {leader : W.ClassId τ} {Γ : TypedSlotContext.{u, v} Ty}
    {leftEmbedding rightEmbedding :
      TypedSlotEmbedding (W.interface leader) Γ}
    (evidence : SameLeaderSymmetryEvidence W leader Γ
      leftEmbedding rightEmbedding) :
    TypedEquationalCertificate L
      (L.rename leftEmbedding (W.witness leader))
      (L.rename rightEmbedding (W.witness leader)) := by
  let transported := TypedEquationalCertificate.transport rightEmbedding
    evidence.symmetryCertificate
  have alignedRight :
      L.rename rightEmbedding
          (L.rename evidence.symmetry.toTypedSlotEmbedding (W.witness leader)) =
        L.rename leftEmbedding (W.witness leader) := by
    rw [L.renameComp]
    exact congrArg (fun embedding => L.rename embedding (W.witness leader))
      evidence.embeddingCompatibility.symm
  exact .symmetric (transported.rewriteRight alignedRight)

/-- Non-circular headline closure.  Coherence comes from an obligation-free
    initial state and local trace induction; the endpoint equation comes from
    finite unfoldings and a derived same-leader symmetry alignment. -/
theorem localCertificatePreservingReachabilityAndFiniteUnfoldingSoundness
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {initial final : TheoremTraceState.{u, v, w, x} L}
    (initialEmpty : initial.Obligation → False)
    (trace : LocalCertifiedTrace initial final)
    {W : TypedWitnessFamily.{u, v, w, y} L}
    {leftClass rightClass leader : W.ClassId τ}
    (leftPath : CertifiedParentPath W leftClass leader)
    (rightPath : CertifiedParentPath W rightClass leader)
    (leftCaller : TypedSlotEmbedding (W.interface leftClass) Γ)
    (rightCaller : TypedSlotEmbedding (W.interface rightClass) Γ)
    {leftTerm rightTerm : L.Term Γ τ}
    (leftRep : FiniteRepresentation L
      (L.rename leftCaller (W.witness leftClass)) leftTerm)
    (rightRep : FiniteRepresentation L
      (L.rename rightCaller (W.witness rightClass)) rightTerm)
    (sameLeader : SameLeaderSymmetryEvidence W leader Γ
      (TypedSlotEmbedding.comp leftCaller leftPath.embedding)
      (TypedSlotEmbedding.comp rightCaller rightPath.embedding))
    (M : TypedModel.{u, v, w, y, z} L) (η : M.Environment Γ) :
    final.Coherent ∧
    TypedEquationalCertificate L leftTerm rightTerm ∧
    M.evaluate leftTerm η = M.evaluate rightTerm η := by
  have finalCoherent := localCertifiedTracePreservesCoherence trace
    (obligationFreeStateIsCoherent initialEmpty)
  have leftCertificate :=
    (findAndFiniteUnfoldingPreserveEquationalCertificates
      leftPath leftCaller leftRep).2
  have rightCertificate :=
    (findAndFiniteUnfoldingPreserveEquationalCertificates
      rightPath rightCaller rightRep).2
  have leaderCertificate :=
    alignedLeaderCertificateOfSameLeaderSymmetry sameLeader
  let resultCertificate := TypedEquationalCertificate.transitive leftCertificate
    (TypedEquationalCertificate.transitive leaderCertificate
      (TypedEquationalCertificate.symmetric rightCertificate))
  exact ⟨finalCoherent, resultCertificate,
    typedCertificateSemanticSoundness M resultCertificate η⟩

end TypedSlottedEGraphsPaper
