import TypedSlottedEGraphsPaper.TraceSemantics

namespace TypedSlottedEGraphsPaper

universe u v w x y z q s

/-!
This file supplies paper-facing wrappers for F23--F27.  In contrast with the
older generic wrappers, graph obligations contain only endpoints and typed
maps: none of the EC, PC, SC, find, unfolding, kernel, collision, or headline
conclusions is stored as an assumption.  Certificates are obtained by
induction over the corresponding proof-relevant traces.
-/

set_option linter.checkUnivs false in
/-- Raw stored-shape, parent-edge, and symmetry-generator data for one fixed
    typed witness family.  These are the three endpoint families appearing in
    the paper's EC, PC, and SC clauses. -/
structure PaperGraphObligations {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    (W : TypedWitnessFamily.{u, v, w, x} L) where
  StoredCase : {τ : Ty} → (a : W.ClassId τ) → Type y
  storedContext : {τ : Ty} → {a : W.ClassId τ} →
    StoredCase a → TypedSlotContext.{u, v} Ty
  storedRealization : {τ : Ty} → {a : W.ClassId τ} →
    (c : StoredCase a) → L.Term (storedContext c) τ
  storedInclusion : {τ : Ty} → {a : W.ClassId τ} →
    (c : StoredCase a) →
      TypedSlotEmbedding (W.interface a) (storedContext c)
  ParentEdge : {τ : Ty} → W.ClassId τ → W.ClassId τ → Type z
  parentEmbedding : {τ : Ty} → {child parent : W.ClassId τ} →
    ParentEdge child parent →
      TypedSlotEmbedding (W.interface parent) (W.interface child)
  SymmetryGenerator : {τ : Ty} → (a : W.ClassId τ) → Type q
  symmetryRenaming : {τ : Ty} → {a : W.ClassId τ} →
    SymmetryGenerator a →
      TypedSlotRenaming (W.interface a) (W.interface a)

/-- F23: the coherent family consists of independently typed EC, PC, and SC
    derivations for every raw graph obligation. -/
structure PaperF23CoherentCertificateFamily {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    (O : PaperGraphObligations.{u, v, w, x, y, z, q} L W) : Prop where
  storedCertificate : ∀ {τ} {a : W.ClassId τ} (c : O.StoredCase a),
    TypedEquationalCertificate L (O.storedRealization c)
      (L.rename (O.storedInclusion c) (W.witness a))
  parentCertificate : ∀ {τ} {child parent : W.ClassId τ}
      (edge : O.ParentEdge child parent),
    TypedEquationalCertificate L (W.witness child)
      (L.rename (O.parentEmbedding edge) (W.witness parent))
  symmetryCertificate : ∀ {τ} {a : W.ClassId τ}
      (generator : O.SymmetryGenerator a),
    TypedEquationalCertificate L (W.witness a)
      (L.rename (O.symmetryRenaming generator).toTypedSlotEmbedding
        (W.witness a))

/-- A raw parent path.  Its edges carry embeddings but do not carry the PC
    conclusion. -/
inductive PaperParentPath {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    (O : PaperGraphObligations.{u, v, w, x, y, z, q} L W) {τ : Ty} :
    W.ClassId τ → W.ClassId τ → Type (max u v w x y z q) where
  | reflexive (a : W.ClassId τ) : PaperParentPath O a a
  | step (edge : O.ParentEdge child parent)
      (rest : PaperParentPath O parent leader) :
      PaperParentPath O child leader

namespace PaperParentPath

def embedding {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W} {τ : Ty}
    {child leader : W.ClassId τ} (path : PaperParentPath O child leader) :
    TypedSlotEmbedding (W.interface leader) (W.interface child) :=
  match path with
  | .reflexive a => TypedSlotEmbedding.id (W.interface a)
  | .step edge rest =>
      TypedSlotEmbedding.comp (O.parentEmbedding edge) (embedding rest)

/-- PC certificates compose along the finite parent path. -/
theorem certificate {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W} {τ : Ty}
    {child leader : W.ClassId τ} (coherent : PaperF23CoherentCertificateFamily O)
    (path : PaperParentPath O child leader) :
    TypedEquationalCertificate L (W.witness child)
      (L.rename path.embedding (W.witness leader)) := by
  induction path with
  | reflexive a =>
      exact (TypedEquationalCertificate.reflexive (W.witness a)).rewriteRight
        (L.renameId (W.witness a)).symm
  | step edge rest ih =>
      apply TypedEquationalCertificate.rewriteRight
        (.transitive (coherent.parentCertificate edge)
          (.transport (O.parentEmbedding edge) ih))
      exact L.renameComp (O.parentEmbedding edge) rest.embedding (W.witness _)

/-- The path certificate transported to an invocation's caller. -/
theorem callerCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W} {τ : Ty}
    {child leader : W.ClassId τ} (coherent : PaperF23CoherentCertificateFamily O)
    (path : PaperParentPath O child leader)
    {Γ : TypedSlotContext.{u, v} Ty}
    (caller : TypedSlotEmbedding (W.interface child) Γ) :
    TypedEquationalCertificate L (L.rename caller (W.witness child))
      (L.rename (TypedSlotEmbedding.comp caller path.embedding)
        (W.witness leader)) := by
  apply TypedEquationalCertificate.rewriteRight
    (.transport caller (path.certificate coherent))
  exact L.renameComp caller path.embedding (W.witness leader)

end PaperParentPath

/-- One locally checked unfolding step is either a declared equation or a
    forward structural-congruence rule.  It is not an arbitrary certificate. -/
inductive CertifiedFiniteUnfoldingStep {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty} :
    L.Term Γ τ → L.Term Γ τ → Prop where
  | primitive (equation : L.PrimitiveEquation left right) :
      CertifiedFiniteUnfoldingStep L left right
  | congruence (rule : L.StructuralCongruence left right) :
      CertifiedFiniteUnfoldingStep L left right
  | symmetric (step : CertifiedFiniteUnfoldingStep L left right) :
      CertifiedFiniteUnfoldingStep L right left

theorem certifiedFiniteUnfoldingStepCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {left right : L.Term Γ τ}
    (step : CertifiedFiniteUnfoldingStep L left right) :
    TypedEquationalCertificate L left right := by
  induction step with
  | primitive equation => exact .primitive equation
  | congruence rule => exact .congruence rule
  | symmetric step inductionHypothesis => exact .symmetric inductionHypothesis

/-- A finite unfolding trace contains only the preceding local leaves.  It
    cannot contain the desired endpoint certificate as a field. -/
inductive CertifiedFiniteUnfoldingTrace {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    (endpoint : L.Term Γ τ) : L.Term Γ τ → Prop where
  | endpoint : CertifiedFiniteUnfoldingTrace L endpoint endpoint
  | expand (localStep : CertifiedFiniteUnfoldingStep L term next)
      (rest : CertifiedFiniteUnfoldingTrace L endpoint next) :
      CertifiedFiniteUnfoldingTrace L endpoint term

theorem certifiedFiniteUnfoldingTraceCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {endpoint term : L.Term Γ τ}
    (trace : CertifiedFiniteUnfoldingTrace L endpoint term) :
    TypedEquationalCertificate L term endpoint := by
  induction trace with
  | endpoint => exact .reflexive endpoint
  | expand localStep rest ih =>
      exact .transitive (certifiedFiniteUnfoldingStepCertificate localStep) ih

/-- A finite representation chooses an actual stored-shape obligation,
    extends its exact interface embedding to the caller, and replays a finite
    congruence-only unfolding trace to that restored shape. -/
structure PaperFiniteUnfolding {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    (O : PaperGraphObligations.{u, v, w, x, y, z, q} L W)
    {τ : Ty} (a : W.ClassId τ) (Γ : TypedSlotContext.{u, v} Ty)
    (caller : TypedSlotEmbedding (W.interface a) Γ)
    (term : L.Term Γ τ) : Type (max u v w x y z q) where
  stored : O.StoredCase a
  extension : TypedSlotEmbedding (O.storedContext stored) Γ
  compatibility : TypedSlotEmbedding.comp extension
    (O.storedInclusion stored) = caller
  trace : CertifiedFiniteUnfoldingTrace L
    (L.rename extension (O.storedRealization stored)) term

/-- EC plus the certified finite trace proves the representation endpoint. -/
theorem paperFiniteUnfoldingCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    (coherent : PaperF23CoherentCertificateFamily O)
    {τ : Ty} {a : W.ClassId τ} {Γ : TypedSlotContext.{u, v} Ty}
    {caller : TypedSlotEmbedding (W.interface a) Γ}
    {term : L.Term Γ τ} (rep : PaperFiniteUnfolding O a Γ caller term) :
    TypedEquationalCertificate L term (L.rename caller (W.witness a)) := by
  let unfolded := certifiedFiniteUnfoldingTraceCertificate rep.trace
  let stored := TypedEquationalCertificate.transport rep.extension
    (coherent.storedCertificate rep.stored)
  have endpointEquality :
      L.rename rep.extension
          (L.rename (O.storedInclusion rep.stored) (W.witness a)) =
        L.rename caller (W.witness a) := by
    rw [L.renameComp]
    exact congrArg (fun e => L.rename e (W.witness a)) rep.compatibility
  exact .transitive unfolded (stored.rewriteRight endpointEquality)

/-- TSG-ATOM-033: coherent PC obligations prove the caller-to-leader find
    witness equation along a raw finite parent path. -/
theorem paperAtom033FindWitnessCertificate
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    (coherent : PaperF23CoherentCertificateFamily O)
    {τ : Ty} {child leader : W.ClassId τ}
    (path : PaperParentPath O child leader)
    {Γ : TypedSlotContext.{u, v} Ty}
    (caller : TypedSlotEmbedding (W.interface child) Γ) :
    TypedEquationalCertificate L (L.rename caller (W.witness child))
      (L.rename (TypedSlotEmbedding.comp caller path.embedding)
        (W.witness leader)) := by
  exact path.callerCertificate coherent caller

/-- TSG-ATOM-034: EC replay for a finite representation followed by PC
    replay for find proves the weakened found-leader endpoint. -/
theorem paperAtom034FiniteUnfoldingWitnessCertificate
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    (coherent : PaperF23CoherentCertificateFamily O)
    {τ : Ty} {child leader : W.ClassId τ}
    (path : PaperParentPath O child leader)
    {Γ : TypedSlotContext.{u, v} Ty}
    (caller : TypedSlotEmbedding (W.interface child) Γ)
    {term : L.Term Γ τ}
    (rep : PaperFiniteUnfolding O child Γ caller term) :
    TypedEquationalCertificate L term
      (L.rename (TypedSlotEmbedding.comp caller path.embedding)
        (W.witness leader)) := by
  exact .transitive (paperFiniteUnfoldingCertificate coherent rep)
    (paperAtom033FindWitnessCertificate coherent path caller)

/-- F24: coherent PC edges prove find, while EC and finite congruence replay
    prove the unfolding endpoint; composing them gives the leader witness. -/
theorem paperF24FindAndFiniteUnfoldingPreserveEquationalCertificates
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    (coherent : PaperF23CoherentCertificateFamily O)
    {τ : Ty} {child leader : W.ClassId τ}
    (path : PaperParentPath O child leader)
    {Γ : TypedSlotContext.{u, v} Ty}
    (caller : TypedSlotEmbedding (W.interface child) Γ) :
    TypedEquationalCertificate L (L.rename caller (W.witness child))
        (L.rename (TypedSlotEmbedding.comp caller path.embedding)
          (W.witness leader)) ∧
      ∀ {term : L.Term Γ τ}, PaperFiniteUnfolding O child Γ caller term →
        TypedEquationalCertificate L term
          (L.rename (TypedSlotEmbedding.comp caller path.embedding)
            (W.witness leader)) := by
  exact ⟨paperAtom033FindWitnessCertificate coherent path caller,
    fun rep =>
      paperAtom034FiniteUnfoldingWitnessCertificate coherent path caller rep⟩

/-- TSG-ATOM-035: two ambient environments that agree after restriction to
    the caller interface give the same value to a finite representation. -/
theorem paperAtom035RedundantCoordinateIndependence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    (coherent : PaperF23CoherentCertificateFamily O)
    {τ : Ty} {a : W.ClassId τ} {Γ : TypedSlotContext.{u, v} Ty}
    {caller : TypedSlotEmbedding (W.interface a) Γ}
    {term : L.Term Γ τ} (rep : PaperFiniteUnfolding O a Γ caller term)
    (model : TypedModel.{u, v, w, s, q} L)
    (leftEnvironment rightEnvironment : model.Environment Γ)
    (sameCallerEnvironment :
      model.restrict caller leftEnvironment =
        model.restrict caller rightEnvironment) :
    model.evaluate term leftEnvironment =
      model.evaluate term rightEnvironment := by
  let certificate := paperFiniteUnfoldingCertificate coherent rep
  calc
    model.evaluate term leftEnvironment =
        model.evaluate (L.rename caller (W.witness a)) leftEnvironment :=
      typedCertificateSemanticSoundness model certificate leftEnvironment
    _ = model.evaluate (W.witness a)
        (model.restrict caller leftEnvironment) :=
      model.renameEvaluation caller (W.witness a) leftEnvironment
    _ = model.evaluate (W.witness a)
        (model.restrict caller rightEnvironment) :=
      congrArg (model.evaluate (W.witness a)) sameCallerEnvironment
    _ = model.evaluate (L.rename caller (W.witness a)) rightEnvironment :=
      (model.renameEvaluation caller (W.witness a) rightEnvironment).symm
    _ = model.evaluate term rightEnvironment :=
      (typedCertificateSemanticSoundness model certificate rightEnvironment).symm

/-- Kernel provenance is a finite derivation tree with only primitive and
    forward-congruence leaves; it cannot store an arbitrary endpoint
    certificate. -/
inductive CertifiedKernelReplay {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty} :
    L.Term Γ τ → L.Term Γ τ → Prop where
  | reflexive (term : L.Term Γ τ) : CertifiedKernelReplay L term term
  | primitive (equation : L.PrimitiveEquation left right) :
      CertifiedKernelReplay L left right
  | congruence (rule : L.StructuralCongruence left right) :
      CertifiedKernelReplay L left right
  | symmetric (trace : CertifiedKernelReplay L left right) :
      CertifiedKernelReplay L right left
  | transitive (head : CertifiedKernelReplay L left middle)
      (tail : CertifiedKernelReplay L middle right) :
      CertifiedKernelReplay L left right

theorem certifiedKernelReplayCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {left right : L.Term Γ τ} (trace : CertifiedKernelReplay L left right) :
    TypedEquationalCertificate L left right := by
  induction trace with
  | reflexive term => exact .reflexive term
  | primitive equation => exact .primitive equation
  | congruence rule => exact .congruence rule
  | symmetric trace ih => exact .symmetric ih
  | transitive head tail ihHead ihTail => exact .transitive ihHead ihTail

/-- The exact kernel, its support inclusion, and replayable provenance. -/
structure PaperCertifiedKernelExtraction {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    (Γ Δ : TypedSlotContext.{u, v} Ty) (τ : Ty) where
  original : L.Term Γ τ
  kernel : L.Term Δ τ
  inclusion : TypedSlotEmbedding Δ Γ
  provenance : CertifiedKernelReplay L original (L.rename inclusion kernel)

/-- F25: replaying retained kernel provenance yields the source-to-kernel
    certificate.  No equation is added by this theorem. -/
theorem paperF25CertifiedLeaderKernelExtraction
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ Δ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    (record : PaperCertifiedKernelExtraction L Γ Δ τ) :
    TypedEquationalCertificate L record.original
      (L.rename record.inclusion record.kernel) :=
  certifiedKernelReplayCertificate record.provenance

/-- A tagged canonical shape explicitly contains its output type and effective
    context, as required by the paper's typed shape equality. -/
structure PaperTypedCanonicalShapeKey (Ty : Type u) (Payload : Type s) where
  output : Ty
  effectiveContext : TypedSlotContext.{u, v} Ty
  payload : Payload

/-- TSG-ATOM-036: equality of tagged canonical shapes forces equality of the
    output-type and effective-context projections. -/
theorem paperAtom036ShapeCollisionTypeSupportConsequences
    {Ty : Type u} {Payload : Type s}
    {left right : PaperTypedCanonicalShapeKey.{u, v, s} Ty Payload}
    (shapeEquality : left = right) :
    left.output = right.output ∧
      left.effectiveContext = right.effectiveContext := by
  exact ⟨congrArg PaperTypedCanonicalShapeKey.output shapeEquality,
    congrArg PaperTypedCanonicalShapeKey.effectiveContext shapeEquality⟩

/-- A certified canonical record transports an exact kernel to a common
    canonical support and replays the permitted normalization steps there. -/
structure PaperCertifiedCanonicalRecord {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    (Γ C : TypedSlotContext.{u, v} Ty) (τ : Ty)
    (Shape : Type s) (canonicalRealization : Shape → L.Term C τ) where
  support : TypedSlotContext.{u, v} Ty
  extraction : PaperCertifiedKernelExtraction L Γ support τ
  supportRenaming : TypedSlotRenaming C support
  shape : Shape
  normalization : CertifiedKernelReplay L
    (L.rename supportRenaming.inverse extraction.kernel)
    (canonicalRealization shape)

/-- The renaming induced by two canonical support alignments. -/
def paperCollisionRenaming {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ₁ Γ₂ C : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {Shape : Type s} {canonicalRealization : Shape → L.Term C τ}
    (left : PaperCertifiedCanonicalRecord L Γ₁ C τ Shape canonicalRealization)
    (right : PaperCertifiedCanonicalRecord L Γ₂ C τ Shape canonicalRealization) :
    TypedSlotRenaming left.support right.support :=
  TypedSlotRenaming.comp right.supportRenaming
    (TypedSlotRenaming.symm left.supportRenaming)

/-- Equal certified canonical realizations yield the directed kernel
    alignment; the proof is normalization replay, equality, and inverse replay. -/
theorem canonicalEqualityYieldsKernelCollision
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ₁ Γ₂ C : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {Shape : Type s} {canonicalRealization : Shape → L.Term C τ}
    (left : PaperCertifiedCanonicalRecord L Γ₁ C τ Shape canonicalRealization)
    (right : PaperCertifiedCanonicalRecord L Γ₂ C τ Shape canonicalRealization)
    (shapeEquality : left.shape = right.shape) :
    TypedEquationalCertificate L
      (L.rename (paperCollisionRenaming left right).toTypedSlotEmbedding
        left.extraction.kernel)
      right.extraction.kernel := by
  let leftNormalization := TypedEquationalCertificate.transport
    right.supportRenaming.toTypedSlotEmbedding
    (certifiedKernelReplayCertificate left.normalization)
  let rightNormalization := TypedEquationalCertificate.transport
    right.supportRenaming.toTypedSlotEmbedding
    (certifiedKernelReplayCertificate right.normalization)
  have leftEndpoint :
      L.rename right.supportRenaming.toTypedSlotEmbedding
          (L.rename left.supportRenaming.inverse left.extraction.kernel) =
        L.rename (paperCollisionRenaming left right).toTypedSlotEmbedding
          left.extraction.kernel := by
    rw [L.renameComp]
    rfl
  have canonicalEquality :
      canonicalRealization left.shape = canonicalRealization right.shape :=
    congrArg canonicalRealization shapeEquality
  have middleEndpoint :
      L.rename right.supportRenaming.toTypedSlotEmbedding
          (canonicalRealization left.shape) =
        L.rename right.supportRenaming.toTypedSlotEmbedding
          (canonicalRealization right.shape) :=
    congrArg (fun term => L.rename right.supportRenaming.toTypedSlotEmbedding term)
      canonicalEquality
  have rightEndpoint :
      L.rename right.supportRenaming.toTypedSlotEmbedding
          (L.rename right.supportRenaming.inverse right.extraction.kernel) =
        right.extraction.kernel := by
    rw [L.renameComp, right.supportRenaming.rightInverse]
    exact L.renameId right.extraction.kernel
  exact .transitive (leftNormalization.rewriteLeft leftEndpoint.symm)
    (.transitive
      ((TypedEquationalCertificate.reflexive
        (L.rename right.supportRenaming.toTypedSlotEmbedding
          (canonicalRealization left.shape))).rewriteRight
          middleEndpoint)
      ((TypedEquationalCertificate.symmetric rightNormalization).rewriteRight
        rightEndpoint))

/-- TSG-ATOM-037: equal shape keys yield the effective-kernel collision
    certificate after both certified normalizations are replayed. -/
theorem paperAtom037EffectiveKernelCollisionCertificate
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ₁ Γ₂ C : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {Shape : Type s} {canonicalRealization : Shape → L.Term C τ}
    (left : PaperCertifiedCanonicalRecord L Γ₁ C τ Shape canonicalRealization)
    (right : PaperCertifiedCanonicalRecord L Γ₂ C τ Shape canonicalRealization)
    (shapeEquality : left.shape = right.shape) :
    TypedEquationalCertificate L
      (L.rename (paperCollisionRenaming left right).toTypedSlotEmbedding
        left.extraction.kernel)
      right.extraction.kernel := by
  exact canonicalEqualityYieldsKernelCollision left right shapeEquality

/-- F26: equality of the certified canonical realizations supplies the kernel
    collision certificate.  Compatible embeddings then compose both F25
    certificates and the collision in one common context. -/
theorem paperF26CertifiedEffectiveShapeCollision
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ₁ Γ₂ C : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {Shape : Type s} {canonicalRealization : Shape → L.Term C τ}
    (left : PaperCertifiedCanonicalRecord L Γ₁ C τ Shape canonicalRealization)
    (right : PaperCertifiedCanonicalRecord L Γ₂ C τ Shape canonicalRealization)
    (shapeEquality : left.shape = right.shape) :
    TypedEquationalCertificate L
        (L.rename (paperCollisionRenaming left right).toTypedSlotEmbedding
          left.extraction.kernel)
        right.extraction.kernel ∧
      ∀ {Ω : TypedSlotContext.{u, v} Ty}
        (e₁ : TypedSlotEmbedding Γ₁ Ω) (e₂ : TypedSlotEmbedding Γ₂ Ω),
        TypedSlotEmbedding.comp e₁ left.extraction.inclusion =
          TypedSlotEmbedding.comp e₂
            (TypedSlotEmbedding.comp right.extraction.inclusion
              (paperCollisionRenaming left right).toTypedSlotEmbedding) →
        TypedEquationalCertificate L (L.rename e₁ left.extraction.original)
          (L.rename e₂ right.extraction.original) := by
  let collision := canonicalEqualityYieldsKernelCollision left right
    shapeEquality
  refine ⟨collision, ?_⟩
  intro Ω e₁ e₂ compatible
  let sourceLeft := TypedEquationalCertificate.transport e₁
    (paperF25CertifiedLeaderKernelExtraction left.extraction)
  let sourceRight := TypedEquationalCertificate.transport e₂
    (paperF25CertifiedLeaderKernelExtraction right.extraction)
  let transportedCollision := TypedEquationalCertificate.transport
    (TypedSlotEmbedding.comp e₂ right.extraction.inclusion) collision
  have sourceLeftEndpoint :
      L.rename e₁
          (L.rename left.extraction.inclusion left.extraction.kernel) =
        L.rename (TypedSlotEmbedding.comp e₁ left.extraction.inclusion)
          left.extraction.kernel :=
    L.renameComp e₁ left.extraction.inclusion left.extraction.kernel
  have collisionLeftEndpoint :
      L.rename (TypedSlotEmbedding.comp e₂ right.extraction.inclusion)
          (L.rename (paperCollisionRenaming left right).toTypedSlotEmbedding
            left.extraction.kernel) =
        L.rename (TypedSlotEmbedding.comp e₁ left.extraction.inclusion)
          left.extraction.kernel := by
    rw [L.renameComp]
    apply congrArg (fun emb => L.rename emb left.extraction.kernel)
    exact (TypedSlotEmbedding.comp_assoc e₂ right.extraction.inclusion
      (paperCollisionRenaming left right).toTypedSlotEmbedding).trans
        compatible.symm
  have collisionRightEndpoint :
      L.rename (TypedSlotEmbedding.comp e₂ right.extraction.inclusion)
          right.extraction.kernel =
        L.rename e₂
          (L.rename right.extraction.inclusion right.extraction.kernel) :=
    (L.renameComp e₂ right.extraction.inclusion
      right.extraction.kernel).symm
  exact .transitive (sourceLeft.rewriteRight sourceLeftEndpoint)
    (.transitive
      (transportedCollision.rewriteLeft collisionLeftEndpoint.symm |>.rewriteRight
        collisionRightEndpoint)
      (.symmetric sourceRight))

/-- TSG-ATOM-038: the two source-to-kernel certificates and the directed
    kernel collision compose under the exact common-context compatibility
    equation. -/
theorem paperAtom038AmbientCollisionCertificate
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ₁ Γ₂ C Ω : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {Shape : Type s} {canonicalRealization : Shape → L.Term C τ}
    (left : PaperCertifiedCanonicalRecord L Γ₁ C τ Shape canonicalRealization)
    (right : PaperCertifiedCanonicalRecord L Γ₂ C τ Shape canonicalRealization)
    (shapeEquality : left.shape = right.shape)
    (e₁ : TypedSlotEmbedding Γ₁ Ω) (e₂ : TypedSlotEmbedding Γ₂ Ω)
    (compatible : TypedSlotEmbedding.comp e₁ left.extraction.inclusion =
      TypedSlotEmbedding.comp e₂
        (TypedSlotEmbedding.comp right.extraction.inclusion
          (paperCollisionRenaming left right).toTypedSlotEmbedding)) :
    TypedEquationalCertificate L (L.rename e₁ left.extraction.original)
      (L.rename e₂ right.extraction.original) := by
  exact (paperF26CertifiedEffectiveShapeCollision left right shapeEquality).2
    e₁ e₂ compatible

/-- One live EC, PC, or SC obligation, retaining all dependent indices. -/
inductive PaperLiveObligation {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    (O : PaperGraphObligations.{u, v, w, x, y, z, q} L W) :
    Type (max u v w x y z q) where
  | stored {τ : Ty} {a : W.ClassId τ} (case : O.StoredCase a) :
      PaperLiveObligation O
  | parent {τ : Ty} {child parentClass : W.ClassId τ}
      (edge : O.ParentEdge child parentClass) : PaperLiveObligation O
  | symmetry {τ : Ty} {a : W.ClassId τ}
      (generator : O.SymmetryGenerator a) : PaperLiveObligation O

namespace PaperLiveObligation

/-- The precise endpoint pair encoded by a live paper obligation. -/
def endpoints {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W} :
    PaperLiveObligation O → TypedEndpointPair L
  | .stored (τ := τ) (a := a) case =>
      { index := { context := O.storedContext case, output := τ }
        left := O.storedRealization case
        right := L.rename (O.storedInclusion case) (W.witness a) }
  | .parent (τ := τ) (child := child) (parentClass := parentClass) edge =>
      { index := { context := W.interface child, output := τ }
        left := W.witness child
        right := L.rename (O.parentEmbedding edge) (W.witness parentClass) }
  | .symmetry (τ := τ) (a := a) generator =>
      { index := { context := W.interface a, output := τ }
        left := W.witness a
        right := L.rename
          (O.symmetryRenaming generator).toTypedSlotEmbedding (W.witness a) }

end PaperLiveObligation

/-- Regard the EC/PC/SC endpoint family as the generic theorem trace state. -/
def paperObligationTraceState {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    (O : PaperGraphObligations.{u, v, w, x, y, z, q} L W) :
    TheoremTraceState L where
  Obligation := PaperLiveObligation O
  endpoints := PaperLiveObligation.endpoints

/-- F23 coherence implies coherence of exactly the encoded trace state. -/
theorem paperF23ToTraceCoherence {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    (coherent : PaperF23CoherentCertificateFamily O) :
    (paperObligationTraceState O).Coherent := by
  intro obligation
  cases obligation with
  | stored case => exact coherent.storedCertificate case
  | parent edge => exact coherent.parentCertificate edge
  | symmetry generator => exact coherent.symmetryCertificate generator

/-- Coherence of the exact encoded trace state reconstructs all three fields
    of F23; there is no untracked endpoint family. -/
theorem paperF23OfTraceCoherence {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    (coherent : (paperObligationTraceState O).Coherent) :
    PaperF23CoherentCertificateFamily O where
  storedCertificate case := coherent (.stored case)
  parentCertificate edge := coherent (.parent edge)
  symmetryCertificate generator := coherent (.symmetry generator)

/-- TSG-ATOM-039: a proof-relevant local trace from an obligation-free state
    establishes all final EC, PC, and SC certificates. -/
theorem paperAtom039CertifiedReachabilityPreservesCoherence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    {initial : TheoremTraceState L}
    (initialEmpty : initial.Obligation → False)
    (trace : LocalCertifiedTrace initial (paperObligationTraceState O)) :
    PaperF23CoherentCertificateFamily O := by
  exact paperF23OfTraceCoherence
    (localCertifiedTracePreservesCoherence trace
      (obligationFreeStateIsCoherent initialEmpty))

/-- A proof-relevant word in the group generated by recorded SC generators. -/
inductive PaperSymmetryWord {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    (O : PaperGraphObligations.{u, v, w, x, y, z, q} L W)
    {τ : Ty} (a : W.ClassId τ) :
    TypedSlotRenaming (W.interface a) (W.interface a) →
    Type (max u v w x y z q) where
  | identity : PaperSymmetryWord O a (TypedSlotRenaming.id (W.interface a))
  | generator (entry : O.SymmetryGenerator a) :
      PaperSymmetryWord O a (O.symmetryRenaming entry)
  | inverse {rho : TypedSlotRenaming (W.interface a) (W.interface a)}
      (word : PaperSymmetryWord O a rho) :
      PaperSymmetryWord O a (TypedSlotRenaming.symm rho)
  | compose {first second :
      TypedSlotRenaming (W.interface a) (W.interface a)}
      (firstWord : PaperSymmetryWord O a first)
      (secondWord : PaperSymmetryWord O a second) :
      PaperSymmetryWord O a (TypedSlotRenaming.comp second first)

/-- The generator SC certificates close under identity, inverse, and
    composition, proving SC for every represented group word. -/
theorem paperF23SymmetryWordCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    (coherent : PaperF23CoherentCertificateFamily O)
    {τ : Ty} {a : W.ClassId τ}
    {rho : TypedSlotRenaming (W.interface a) (W.interface a)}
    (word : PaperSymmetryWord O a rho) :
    TypedEquationalCertificate L (W.witness a)
      (L.rename rho.toTypedSlotEmbedding (W.witness a)) := by
  induction word with
  | identity =>
      exact (TypedEquationalCertificate.reflexive (W.witness a)).rewriteRight
        (L.renameId (W.witness a)).symm
  | generator entry => exact coherent.symmetryCertificate entry
  | @inverse base word inductionHypothesis =>
      let transported := TypedEquationalCertificate.transport
        base.inverse inductionHypothesis
      have rightEndpoint :
          L.rename base.inverse
              (L.rename base.toTypedSlotEmbedding (W.witness a)) =
            W.witness a := by
        rw [L.renameComp, base.leftInverse]
        exact L.renameId (W.witness a)
      exact .symmetric (transported.rewriteRight rightEndpoint)
  | @compose first second firstWord secondWord firstIH secondIH =>
      let transportedFirst := TypedEquationalCertificate.transport
        second.toTypedSlotEmbedding firstIH
      have rightEndpoint :
          L.rename second.toTypedSlotEmbedding
              (L.rename first.toTypedSlotEmbedding (W.witness a)) =
            L.rename (TypedSlotRenaming.comp second first).toTypedSlotEmbedding
              (W.witness a) := by
        rw [L.renameComp]
        rfl
      exact .transitive secondIH
        (transportedFirst.rewriteRight rightEndpoint)

/-- Same-leader alignment names a generated SC word and the exact embedding
    equation only.  Its equational certificate is derived from F23. -/
structure PaperSameLeaderSymmetry {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    (O : PaperGraphObligations.{u, v, w, x, y, z, q} L W)
    {τ : Ty} (leader : W.ClassId τ) (Γ : TypedSlotContext.{u, v} Ty)
    (leftEmbedding rightEmbedding :
      TypedSlotEmbedding (W.interface leader) Γ) :
    Type (max u v w x y z q) where
  rho : TypedSlotRenaming (W.interface leader) (W.interface leader)
  word : PaperSymmetryWord O leader rho
  embeddingCompatibility : leftEmbedding = TypedSlotEmbedding.comp
    rightEmbedding rho.toTypedSlotEmbedding

/-- The leader equation is SC transported to the caller and rewritten by the
    checked alignment equation. -/
theorem paperAlignedLeaderCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    (coherent : PaperF23CoherentCertificateFamily O)
    {τ : Ty} {leader : W.ClassId τ} {Γ : TypedSlotContext.{u, v} Ty}
    {leftEmbedding rightEmbedding :
      TypedSlotEmbedding (W.interface leader) Γ}
    (alignment : PaperSameLeaderSymmetry O leader Γ
      leftEmbedding rightEmbedding) :
    TypedEquationalCertificate L
      (L.rename leftEmbedding (W.witness leader))
      (L.rename rightEmbedding (W.witness leader)) := by
  let transported := TypedEquationalCertificate.transport rightEmbedding
    (paperF23SymmetryWordCertificate coherent alignment.word)
  have alignedRight :
      L.rename rightEmbedding
          (L.rename alignment.rho.toTypedSlotEmbedding
            (W.witness leader)) =
        L.rename leftEmbedding (W.witness leader) := by
    rw [L.renameComp]
    exact congrArg (fun embedding => L.rename embedding (W.witness leader))
      alignment.embeddingCompatibility.symm
  exact .symmetric (transported.rewriteRight alignedRight)

/-- TSG-ATOM-040: two certified finite unfoldings reaching one leader and
    aligned by a generated SC word are equationally equal. -/
theorem paperAtom040FiniteUnfoldingEquationalSoundness
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    (coherent : PaperF23CoherentCertificateFamily O)
    {τ : Ty} {leftClass rightClass leader : W.ClassId τ}
    (leftPath : PaperParentPath O leftClass leader)
    (rightPath : PaperParentPath O rightClass leader)
    {Γ : TypedSlotContext.{u, v} Ty}
    (leftCaller : TypedSlotEmbedding (W.interface leftClass) Γ)
    (rightCaller : TypedSlotEmbedding (W.interface rightClass) Γ)
    {leftTerm rightTerm : L.Term Γ τ}
    (leftRep : PaperFiniteUnfolding O leftClass Γ leftCaller leftTerm)
    (rightRep : PaperFiniteUnfolding O rightClass Γ rightCaller rightTerm)
    (sameLeader : PaperSameLeaderSymmetry O leader Γ
      (TypedSlotEmbedding.comp leftCaller leftPath.embedding)
      (TypedSlotEmbedding.comp rightCaller rightPath.embedding)) :
    TypedEquationalCertificate L leftTerm rightTerm := by
  have leftCertificate :=
    paperAtom034FiniteUnfoldingWitnessCertificate coherent leftPath leftCaller
      leftRep
  have rightCertificate :=
    paperAtom034FiniteUnfoldingWitnessCertificate coherent rightPath rightCaller
      rightRep
  have leaderCertificate := paperAlignedLeaderCertificate coherent sameLeader
  exact .transitive leftCertificate
    (.transitive leaderCertificate (.symmetric rightCertificate))

/-- TSG-ATOM-041: finite equational certificates are sound in every typed
    model under every environment. -/
theorem paperAtom041FiniteUnfoldingModelSoundness
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {leftTerm rightTerm : L.Term Γ τ}
    (certificate : TypedEquationalCertificate L leftTerm rightTerm)
    (model : TypedModel.{u, v, w, s, q} L)
    (environment : model.Environment Γ) :
    model.evaluate leftTerm environment =
      model.evaluate rightTerm environment := by
  exact typedCertificateSemanticSoundness model certificate environment

/-- A certificate remains valid after two embeddings into one common context
    when their restrictions to the represented caller are equal. -/
theorem commonContextWeakeningCertificate {Ty : Type u}
    {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ Ω : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {left right : L.Term Γ τ}
    (certificate : TypedEquationalCertificate L left right)
    (leftEmbedding rightEmbedding : TypedSlotEmbedding Γ Ω)
    (compatible : leftEmbedding = rightEmbedding) :
    TypedEquationalCertificate L (L.rename leftEmbedding left)
      (L.rename rightEmbedding right) := by
  let transported := TypedEquationalCertificate.transport leftEmbedding certificate
  have rightEndpoint : L.rename leftEmbedding right =
      L.rename rightEmbedding right :=
    congrArg (fun embedding => L.rename embedding right) compatible
  exact transported.rewriteRight rightEndpoint

/-- TSG-ATOM-042: the finite-unfolding equality remains valid in a common
    typed context when the two embeddings agree on the caller. -/
theorem paperAtom042CommonContextWeakenedFiniteUnfoldingSoundness
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {Γ Ω : TypedSlotContext.{u, v} Ty} {τ : Ty}
    {leftTerm rightTerm : L.Term Γ τ}
    (certificate : TypedEquationalCertificate L leftTerm rightTerm)
    (leftEmbedding rightEmbedding : TypedSlotEmbedding Γ Ω)
    (compatible : leftEmbedding = rightEmbedding) :
    TypedEquationalCertificate L (L.rename leftEmbedding leftTerm)
      (L.rename rightEmbedding rightTerm) := by
  exact commonContextWeakeningCertificate certificate leftEmbedding
    rightEmbedding compatible

/-- F27: a proof-relevant trace built from the nine local transition families
    establishes final EC/PC/SC coherence.  F24 and a recorded SC generator then
    give equational and model soundness; compatible common-context weakening is
    derived by transport. -/
theorem paperF27CertificatePreservingReachabilityAndFiniteUnfoldingSoundness
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {O : PaperGraphObligations.{u, v, w, x, y, z, q} L W}
    {initial : TheoremTraceState L}
    (initialEmpty : initial.Obligation → False)
    (trace : LocalCertifiedTrace initial (paperObligationTraceState O)) :
    PaperF23CoherentCertificateFamily O ∧
      ∀ {τ : Ty} {leftClass rightClass leader : W.ClassId τ}
        (leftPath : PaperParentPath O leftClass leader)
        (rightPath : PaperParentPath O rightClass leader)
        {Γ : TypedSlotContext.{u, v} Ty}
        (leftCaller : TypedSlotEmbedding (W.interface leftClass) Γ)
        (rightCaller : TypedSlotEmbedding (W.interface rightClass) Γ)
        {leftTerm rightTerm : L.Term Γ τ}
        (_leftRep : PaperFiniteUnfolding O leftClass Γ leftCaller leftTerm)
        (_rightRep : PaperFiniteUnfolding O rightClass Γ rightCaller rightTerm)
        (_sameLeader : PaperSameLeaderSymmetry O leader Γ
          (TypedSlotEmbedding.comp leftCaller leftPath.embedding)
          (TypedSlotEmbedding.comp rightCaller rightPath.embedding)),
        TypedEquationalCertificate L leftTerm rightTerm ∧
          (∀ (model : TypedModel.{u, v, w, s, q} L)
            (environment : model.Environment Γ),
            model.evaluate leftTerm environment =
              model.evaluate rightTerm environment) ∧
          ∀ (Ω : TypedSlotContext.{u, v} Ty)
            (leftEmbedding rightEmbedding : TypedSlotEmbedding Γ Ω),
            leftEmbedding = rightEmbedding →
            TypedEquationalCertificate L (L.rename leftEmbedding leftTerm)
              (L.rename rightEmbedding rightTerm) := by
  have coherent : PaperF23CoherentCertificateFamily O :=
    paperAtom039CertifiedReachabilityPreservesCoherence initialEmpty trace
  refine ⟨coherent, ?_⟩
  intro τ leftClass rightClass leader leftPath rightPath Γ leftCaller
    rightCaller leftTerm rightTerm leftRep rightRep sameLeader
  let resultCertificate := paperAtom040FiniteUnfoldingEquationalSoundness
    coherent leftPath rightPath leftCaller rightCaller leftRep rightRep sameLeader
  exact ⟨resultCertificate,
    fun model environment =>
      paperAtom041FiniteUnfoldingModelSoundness resultCertificate model environment,
    fun Ω leftEmbedding rightEmbedding compatible =>
      paperAtom042CommonContextWeakenedFiniteUnfoldingSoundness resultCertificate
        leftEmbedding rightEmbedding compatible⟩

end TypedSlottedEGraphsPaper
