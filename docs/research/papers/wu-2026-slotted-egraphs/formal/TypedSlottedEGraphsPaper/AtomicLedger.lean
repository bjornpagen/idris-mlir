import TypedSlottedEGraphsPaper.StructuralSemantics
import TypedSlottedEGraphsPaper.TraceSemantics

namespace TypedSlottedEGraphsPaper.AtomicLedger

universe u v w x y z

/-! Foundational carriers. -/

/-- A natural-valued function with finite support. -/
def HasFiniteNatSupport {X : Type u} (count : X -> Nat) : Prop :=
  Exists fun support : List X =>
    forall value, count value ≠ 0 -> value ∈ support

/-- A finite bag is extensionally represented by its multiplicity function.
    Its cardinality field is checked against one duplicate-free enumeration
    of the finite support. -/
structure FiniteBag (X : Type u) where
  count : X -> Nat
  finiteSupport : HasFiniteNatSupport count
  cardinality : Nat
  cardinalityExact : Exists fun support : List X =>
    List.Nodup support ∧
    (forall value, value ∈ support ↔ count value ≠ 0) ∧
    cardinality = (support.map count).sum

/-- A finite set is extensionally represented by its membership predicate. -/
structure FiniteSet (X : Type u) where
  contains : X -> Prop
  finiteSupport : Exists fun support : List X =>
    List.Nodup support ∧ forall value, contains value ↔ value ∈ support

/-- The arity-restricted subcarrier K^J. -/
def ArityRestricted (Carrier : Type u) (size : Carrier -> Nat)
    (J : Nat -> Prop) :=
  { value : Carrier // J (size value) }

abbrev PositiveArity (Carrier : Type u) (size : Carrier -> Nat) :=
  ArityRestricted Carrier size (fun n => 0 < n)

abbrev ZeroInclusiveArity (Carrier : Type u) (size : Carrier -> Nat) :=
  ArityRestricted Carrier size (fun _ => True)

abbrev ExactArity (Carrier : Type u) (size : Carrier -> Nat) (k : Nat) :=
  ArityRestricted Carrier size (fun n => n = k)

/-- The disjoint sum of the four schematic key families. -/
inductive TaggedKey
    (FixedOperator SequenceOperator BagOperator SetOperator X : Type u)
    (fixedArity : FixedOperator -> Nat) where
  | fixed (operator : FixedOperator) (children : List X)
      (arityExact : children.length = fixedArity operator)
  | sequence (operator : SequenceOperator) (children : List X)
  | bag (operator : BagOperator) (children : FiniteBag X)
  | set (operator : SetOperator) (children : FiniteSet X)

/-- TSG-FND-004: all displayed carriers and the required nonempty arity set
    are exposed by one declaration. -/
structure FiniteContainerCarrierDefinition
    (FixedOperator SequenceOperator BagOperator SetOperator X : Type u)
    (fixedArity : FixedOperator -> Nat) where
  Sequence : Type u
  Bag : Type u
  Set : Type u
  arities : Nat -> Prop
  aritiesNonempty : Exists arities
  Key : Type u
  sequenceExact : Sequence = List X
  bagExact : Bag = FiniteBag X
  setExact : Set = FiniteSet X
  Restricted : (Carrier : Type u) → (Carrier → Nat) → (Nat → Prop) → Type u
  Positive : (Carrier : Type u) → (Carrier → Nat) → Type u
  ZeroInclusive : (Carrier : Type u) → (Carrier → Nat) → Type u
  Exact : (Carrier : Type u) → (Carrier → Nat) → Nat → Type u
  restrictedExact : ∀ Carrier size J,
    Restricted Carrier size J = ArityRestricted Carrier size J
  positiveExact : ∀ Carrier size,
    Positive Carrier size = PositiveArity Carrier size
  zeroInclusiveExact : ∀ Carrier size,
    ZeroInclusive Carrier size = ZeroInclusiveArity Carrier size
  exactArityExact : ∀ Carrier size k,
    Exact Carrier size k = ExactArity Carrier size k
  keyExact : Key =
    TaggedKey FixedOperator SequenceOperator BagOperator SetOperator X fixedArity

/-! Binder occurrences and local law licenses. -/

/-- TSG-FND-006: the fresh bound context and descriptor alignment belonging
    to one block occurrence.  A shared name carrier makes disjointness an
    actual proposition rather than an artifact of separate Lean types. -/
structure BinderDescriptorOccurrence {Ty : Type u} (Name : Type v)
    (descriptor caller : TypedSlotContext.{u, w} Ty) where
  bound : TypedSlotContext.{u, w} Ty
  callerName : caller.Slot -> Name
  boundName : bound.Slot -> Name
  callerNameInjective : Function.Injective callerName
  boundNameInjective : Function.Injective boundName
  freshForCaller : forall boundSlot callerSlot,
    boundName boundSlot ≠ callerName callerSlot
  alignment : TypedSlotRenaming descriptor bound

inductive LocalLawKind where
  | associative
  | commutative
  | idempotent
  | unit
  deriving DecidableEq, Repr

/-- Laws certified at one exact type-instantiated operator and schema path. -/
structure ExactPathLawSet (Operator Path : Type u) where
  operator : Operator
  path : Path
  certified : LocalLawKind -> Prop

/-- Carrier-imposed sibling quotient laws. -/
def CarrierRequires (kind : ContainerKind) (law : LocalLawKind) : Prop :=
  match kind with
  | ContainerKind.seq => False
  | ContainerKind.bag => law = LocalLawKind.commutative
  | ContainerKind.set =>
      law = LocalLawKind.commutative ∨ law = LocalLawKind.idempotent

/-- TSG-FND-007: a well-formed path contains every law required by its
    structural carrier. -/
def SignaturePathLawful {Operator Path : Type u}
    (kind : ContainerKind) (laws : ExactPathLawSet Operator Path) : Prop :=
  forall law, CarrierRequires kind law -> laws.certified law

/-- TSG-INV-001: the closure invariant for a set-valued port. -/
def SetArityDownwardClosed (J : Nat -> Prop) : Prop :=
  forall k, J k -> 0 < k -> forall j, 1 <= j -> j <= k -> J j

/-- TSG-INV-002: the closure invariant for visible same-head splicing. -/
def FlatAritySpliceClosed (J : Nat -> Prop) : Prop :=
  forall k, J k -> forall l, J l -> 0 < k -> J (k + l - 1)

/-- Type and source-role equality needed for a legal splice. -/
structure FlatRoleCompatibility (Ty : Type u) (Role : Type x) where
  elementType : Ty
  resultType : Ty
  sourceRole : Role
  nestedRole : Role
  sameType : elementType = resultType
  sameRole : sourceRole = nestedRole

/-! Endpoint-indexed law families. -/

/-- One exact pair of typed endpoints and its finite checked derivation. -/
structure CertifiedEndpointPair {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty) where
  context : TypedSlotContext.{u, v} Ty
  output : Ty
  left : L.Term context output
  right : L.Term context output
  certificate : TypedEquationalCertificate L left right

/-- TSG-FND-010: source-unit and empty-occurrence deletion certificates. -/
structure UnitEndpointCertificateFamily {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    (EmptyCase DeletionCase : Type x) (UnitTerm : Type y) where
  sourceUnit : UnitTerm
  emptyApplication : EmptyCase -> CertifiedEndpointPair L
  deleteEmptyNested : DeletionCase -> CertifiedEndpointPair L

/-- TSG-FND-008: the complete license at one exact operator/root path.  The
    algebraic evidence is endpoint-indexed certificate data, not a Boolean
    annotation. -/
structure FlatLicense {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    (Operator Path Role : Type x)
    (AssociativityCase EmptyCase DeletionCase : Type y)
    (UnitTerm : Type z) where
  operator : Operator
  rootPath : Path
  arities : Nat -> Prop
  oneRootContainerSource : Prop
  rootSourceChecked : oneRootContainerSource
  compatibility : FlatRoleCompatibility Ty Role
  associativity : AssociativityCase -> CertifiedEndpointPair L
  spliceClosed : FlatAritySpliceClosed arities
  unitFamily : arities 0 ->
    UnitEndpointCertificateFamily L EmptyCase DeletionCase UnitTerm

/-- TSG-FND-009: C, I, and A are families of endpoint-indexed certificates,
    not trusted labels.  Case indices retain all local typing, arity, profile,
    operator, path, and filling data. -/
structure CIAEndpointCertificateFamilies {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    (PermutationCase QuotientCase SpliceCase : Type x) where
  commutative : PermutationCase -> CertifiedEndpointPair L
  idempotent : QuotientCase -> CertifiedEndpointPair L
  associative : SpliceCase -> CertifiedEndpointPair L

/-! Visible same-head construction. -/

/-- A structural view exposes children only for the same exact head; all
    other syntax stays opaque. -/
structure SameHeadView (Head Child : Type u) where
  headOf : Child -> Option Head
  exposedChildren : Head -> Child -> Option (List Child)
  exposedOnlyAtSameHead : forall head child children,
    exposedChildren head child = some children -> headOf child = some head

/-- One bounded expansion pass.  Iterating this function to a fixed point is
    the recursive smart-constructor behavior. -/
def flattenVisibleSameHeadOnce {Head Child : Type u}
    (view : SameHeadView Head Child) (head : Head) : List Child -> List Child
  | [] => []
  | child :: rest =>
      match view.exposedChildren head child with
      | none => child :: flattenVisibleSameHeadOnce view head rest
      | some nested => nested ++ flattenVisibleSameHeadOnce view head rest

/-- A finite expansion trace whose terminal list has no visible same-head
    child.  This avoids assuming that arbitrary user-supplied syntax trees are
    well founded. -/
inductive VisibleFlattenTrace {Head Child : Type u}
    (view : SameHeadView Head Child) (head : Head) :
    List Child -> List Child -> Type u where
  | done (children : List Child)
      (terminal : forall child, child ∈ children ->
        view.exposedChildren head child = none) :
      VisibleFlattenTrace view head children children
  | expand {before after result}
      (changed : flattenVisibleSameHeadOnce view head before = after)
      (tail : VisibleFlattenTrace view head after result) :
      VisibleFlattenTrace view head before result

/-- TSG-ALG-001: every construction supplies the complete finite recursive
    expansion trace and constructs only its terminal opaque list. -/
structure FlatSmartConstructorContract (Head Child Result : Type u) where
  view : SameHeadView Head Child
  constructOpaqueList : Head -> List Child -> Result
  normalize : Head -> List Child -> List Child
  trace : forall head children,
    VisibleFlattenTrace view head children (normalize head children)
  construct : Head -> List Child -> Result
  constructExact : forall head children,
    construct head children = constructOpaqueList head (normalize head children)

/-! Main structural algorithm definitions. -/

def factorial : Nat -> Nat
  | 0 => 1
  | n + 1 => (n + 1) * factorial n

/-- TSG-DEF-014: repeated occurrences remain repeated in the two input
    lists, exactly matching the displayed product and sum. -/
def canonicalizationWorkFactor
    (typeFiberSizes blockAutomorphismSizes invocationLeaderGroupSizes :
      List Nat) : Nat :=
  (typeFiberSizes.map factorial).prod *
  blockAutomorphismSizes.prod *
  (1 + invocationLeaderGroupSizes.sum)

/-- A complete theorem-facing canonical record. -/
structure CanonicalStructuralRecord {Ty : Type u}
    (Kernel Shape Witness Provenance : Type v)
    (shapeOutput : Shape -> Ty)
    (shapeContext : Shape -> TypedSlotContext.{u, w} Ty)
    (inputContext : TypedSlotContext.{u, w} Ty) where
  kernel : Kernel
  shape : Shape
  output : Ty
  effectiveContext : TypedSlotContext.{u, w} Ty
  shapeWitness : Witness
  inclusion : TypedSlotEmbedding effectiveContext inputContext
  ambientTransport : TypedSlotEmbedding (shapeContext shape) inputContext
  provenance : List Provenance
  outputExact : output = shapeOutput shape
  contextExact : effectiveContext = shapeContext shape
  witnessRenaming : TypedSlotRenaming (shapeContext shape) effectiveContext
  ambientFactorization : ambientTransport =
    TypedSlotEmbedding.comp inclusion witnessRenaming.toTypedSlotEmbedding

/-- Finite candidate enumeration with a deterministic least result. -/
structure CanonicalCandidateSelection (Candidate : Type u)
    [Std.LinearOrderPackage Candidate] where
  candidates : List Candidate
  candidatesNonempty : candidates ≠ []
  complete : Candidate -> Prop
  everyCompleteCandidate : forall candidate,
    complete candidate -> candidate ∈ candidates
  selected : Candidate
  selectedPresent : selected ∈ candidates
  selectedLeast : forall candidate, candidate ∈ candidates -> selected <= candidate

/-- TSG-ALG-002: total finite structural canonicalization returns the least
    complete candidate; only its shape projection is the collision key. -/
structure DirectFiniteCanonicalizationContract
    (Input Candidate Record Shape : Type u)
    [Std.LinearOrderPackage Candidate] where
  enumerate : Input -> CanonicalCandidateSelection Candidate
  canonicalize : Input -> Record
  candidateOf : Record -> Candidate
  shapeOf : Record -> Shape
  selectedExactly : forall input,
    candidateOf (canonicalize input) = (enumerate input).selected
  collisionKey : Input -> Shape
  collisionKeyExact : forall input,
    collisionKey input = shapeOf (canonicalize input)

/-! The two anti-injectivity counterexamples. -/

/-- TSG-CE-001: a constant parent erases a visible swap asymmetry. -/
theorem parentEqualityDoesNotImplyChildSymmetry :
    Exists fun witness : Bool × Bool -> Bool =>
    Exists fun swap : Bool × Bool -> Bool × Bool =>
    Exists fun parent : Bool -> Bool =>
    Exists fun input : Bool × Bool =>
      parent (witness input) = parent (witness (swap input)) ∧
      witness input ≠ witness (swap input) := by
  refine ⟨(fun pair => pair.1), (fun pair => (pair.2, pair.1)),
    (fun _ => false), (true, false), ?_, ?_⟩
  · rfl
  · decide

/-- TSG-CE-002: no empty-context Boolean value realizes the identity
    function on a one-slot Boolean context. -/
theorem properEmbeddingDoesNotImplyIndependence :
    forall emptyWitness : Unit -> Bool,
      ¬(forall input : Bool, input = emptyWitness ()) := by
  intro emptyWitness hypothesis
  have falseCase := hypothesis false
  have trueCase := hypothesis true
  have impossible : false = true := falseCase.trans trueCase.symm
  cases impossible

/-! Small atomic consequences missing a dedicated declaration. -/

/-- TSG-ATOM-008. -/
theorem embeddedNodeOutputTypeUnchanged
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {output : Ty}
    (node : ConcreteFlexibleArityENode signature source output) :
    ConcreteFlexibleArityENode.output
        (ConcreteFlexibleArityENode.act embedding node) =
      ConcreteFlexibleArityENode.output node := by
  rfl

/-- TSG-ATOM-013. -/
theorem invocationActionComposition
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    {caller target : TypedSlotContext.{u, v} Ty}
    (classId : ClassId)
    (inner : TypedSlotEmbedding (signature.classInterface classId) caller)
    (outer : TypedSlotEmbedding caller target) :
    ConcretePort.act outer (concreteInvocation signature classId inner) =
      concreteInvocation signature classId
        (TypedSlotEmbedding.comp outer inner) := by
  rfl

/-- TSG-ATOM-017: the repaired dependent-carrier relation is an equivalence. -/
theorem dependentCarrierAlphaEquivalence
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (bound : List Ty) :
    Equivalence (UnindexedStructuralAlpha Q bound) := by
  exact ⟨unindexedStructuralAlphaReflexive Q bound,
    unindexedStructuralAlphaSymmetric Q bound,
    unindexedStructuralAlphaTransitive Q bound⟩

/-- TSG-ATOM-018: identity, inverse, and composition specialized to the
    intrinsically typed structural node carrier. -/
theorem nodeAlphaGroupoidLaws
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (bound : List Ty) :
    (forall value, UnindexedStructuralAlpha Q bound value value) ∧
    (forall {left right}, UnindexedStructuralAlpha Q bound left right ->
      UnindexedStructuralAlpha Q bound right left) ∧
    (forall {left middle right},
      UnindexedStructuralAlpha Q bound left middle ->
      UnindexedStructuralAlpha Q bound middle right ->
      UnindexedStructuralAlpha Q bound left right) := by
  exact ⟨unindexedStructuralAlphaReflexive Q bound,
    unindexedStructuralAlphaSymmetric Q bound,
    unindexedStructuralAlphaTransitive Q bound⟩

/-- TSG-ATOM-019. -/
theorem nodeAlphaPreservesOutputType
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (bound : List Ty)
    {left right : UnindexedStructuralAlphaCarrier A Block blockTypes Operator bound}
    (related : UnindexedStructuralAlpha Q bound left right) :
    unindexedStructuralAlphaOutput left =
      unindexedStructuralAlphaOutput right := by
  exact (indexedStructuralAlphaEquivalenceLaws Q bound).2.2.2 related

/-- TSG-ATOM-023: quotient-first normalization preserves schema and output. -/
theorem quotientNormalizerPreservesSchemaAndOutput
    {Value : Type u} {Support : Type v} {Schema : Type w} {Output : Type x}
    (P : QuotientNormalFormPresentation Value Support Schema Output)
    (value : Value) :
    P.schema (P.normal value) = P.schema value ∧
    P.output (P.normal value) = P.output value := by
  have related : P.related value (P.normal value) := P.reducesToNormal value
  exact ⟨(P.schemaInvariant related).symm,
    (P.outputInvariant related).symm⟩

/-- TSG-ATOM-024: the port proof applies unchanged to a node carrier. -/
theorem quotientNormalizerNodeSoundnessExactnessAndSupport
    {Node : Type u} {Support : Type v} {Schema : Type w} {Output : Type x}
    (P : QuotientNormalFormPresentation Node Support Schema Output)
    (left right : Node) :
    P.related (P.normal left) left ∧
    (P.normal left = P.normal right ↔ P.related left right) ∧
    P.support (P.normal left) = P.support left := by
  have full := ambientQuotientNormalFormExactness P left right
  exact ⟨full.1, full.2.1, full.2.2.1⟩

/-- TSG-ATOM-027: equality of canonical shapes forces equality of their
    output indices. -/
theorem canonicalShapeEqualityPreservesOutput
    {Node : Type u} {Kernel : Type v} {Support : Type w} {Output : Type x}
    (C : EffectiveShapeSystem Node Kernel Support Output)
    {left right : Node}
    (sameShape : C.canonicalShape left = C.canonicalShape right) :
    C.quotient.output (C.kernel left) =
      C.quotient.output (C.kernel right) := by
  have leftRelated :
      C.quotient.related (C.kernel left) (C.canonicalShape left) :=
    C.quotient.reducesToNormal (C.kernel left)
  have rightRelated :
      C.quotient.related (C.kernel right) (C.canonicalShape right) :=
    C.quotient.reducesToNormal (C.kernel right)
  calc
    C.quotient.output (C.kernel left) =
        C.quotient.output (C.canonicalShape left) :=
      C.quotient.outputInvariant leftRelated
    _ = C.quotient.output (C.canonicalShape right) := by rw [sameShape]
    _ = C.quotient.output (C.kernel right) :=
      (C.quotient.outputInvariant rightRelated).symm

/-- TSG-ATOM-029: a descriptor-local automorphism constructor yields equal
    evaluations for the two complete binder blocks. -/
theorem binderBlockAutomorphismEvaluationInvariant
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (M : TypedModel L)
    {source target : TypedSlotContext.{u, v} Ty}
    {alignment : TypedSlotEmbedding source target}
    {bound : List Ty} {output : Ty} (descriptor : Block)
    (localLaw : Q.BlockAutomorphism descriptor)
    {left : StructuralSyntax A Block blockTypes Operator source
      (blockTypes descriptor ++ bound) output}
    {right : StructuralSyntax A Block blockTypes Operator target
      (blockTypes descriptor ++ bound) output}
    (body : StructuralDerivation Q alignment left right) :
    forall environment : M.Environment target,
      M.evaluate (L.rename alignment
        (R.realize (.binderBlock descriptor left))) environment =
      M.evaluate (R.realize (.binderBlock descriptor right)) environment := by
  exact typedCertificateSemanticSoundness M
    (structuralPortAndNodeCongruenceSoundness Q
      (.binderBlockAutomorphism descriptor localLaw body))

/-- TSG-ATOM-031: certificate soundness gives the graph-relative semantic
    equality in every lawful model. -/
theorem certifiedGraphRelativeSemanticEquality
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (M : TypedModel L)
    {source target : TypedSlotContext.{u, v} Ty}
    {alignment : TypedSlotEmbedding source target}
    {bound : List Ty} {output : Ty}
    {left : StructuralSyntax A Block blockTypes Operator source bound output}
    {right : StructuralSyntax A Block blockTypes Operator target bound output}
    (derivation : StructuralDerivation Q alignment left right) :
    forall environment : M.Environment target,
      M.evaluate (L.rename alignment (R.realize left)) environment =
        M.evaluate (R.realize right) environment :=
  typedCertificateSemanticSoundness M
    (structuralPortAndNodeCongruenceSoundness Q derivation)

/-- TSG-ATOM-032: identity alignment removes all transport from the node
    equation. -/
theorem sameContextIdentityCongruence
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    {context : TypedSlotContext.{u, v} Ty}
    {bound : List Ty} {output : Ty}
    {left right : StructuralSyntax A Block blockTypes Operator context bound output}
    (derivation : StructuralDerivation Q
      (TypedSlotEmbedding.id context) left right) :
    TypedEquationalCertificate L (R.realize left) (R.realize right) := by
  exact TypedEquationalCertificate.rewriteLeft
    (L.renameId (R.realize left)).symm
    (structuralPortAndNodeCongruenceSoundness Q derivation)

/-- TSG-ATOM-035: every two finite restorations of one endpoint are
    equationally equal. -/
theorem redundantCoordinateIndependence
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {context : TypedSlotContext.{u, v} Ty} {output : Ty}
    {endpoint left right : L.Term context output}
    (leftRep : FiniteRepresentation L endpoint left)
    (rightRep : FiniteRepresentation L endpoint right) :
    TypedEquationalCertificate L left right := by
  exact .transitive (finiteRepresentationCertificate leftRep)
    (.symmetric (finiteRepresentationCertificate rightRep))

/-- TSG-ATOM-040: finite unfoldings aligned at one certified leader are
    equationally equal. -/
theorem finiteUnfoldingEquationalSoundness
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {caller : TypedSlotContext.{u, v} Ty} {output : Ty}
    {W : TypedWitnessFamily.{u, v, w, x} L}
    {leftClass rightClass leader : W.ClassId output}
    (leftPath : CertifiedParentPath W leftClass leader)
    (rightPath : CertifiedParentPath W rightClass leader)
    (leftCaller : TypedSlotEmbedding (W.interface leftClass) caller)
    (rightCaller : TypedSlotEmbedding (W.interface rightClass) caller)
    {leftTerm rightTerm : L.Term caller output}
    (leftRep : FiniteRepresentation L
      (L.rename leftCaller (W.witness leftClass)) leftTerm)
    (rightRep : FiniteRepresentation L
      (L.rename rightCaller (W.witness rightClass)) rightTerm)
    (sameLeader : SameLeaderSymmetryEvidence W leader caller
      (TypedSlotEmbedding.comp leftCaller leftPath.embedding)
      (TypedSlotEmbedding.comp rightCaller rightPath.embedding)) :
    TypedEquationalCertificate L leftTerm rightTerm := by
  have leftCertificate :=
    (findAndFiniteUnfoldingPreserveEquationalCertificates
      leftPath leftCaller leftRep).2
  have rightCertificate :=
    (findAndFiniteUnfoldingPreserveEquationalCertificates
      rightPath rightCaller rightRep).2
  have leaderCertificate := alignedLeaderCertificateOfSameLeaderSymmetry sameLeader
  exact .transitive leftCertificate
    (.transitive leaderCertificate (.symmetric rightCertificate))

/-- TSG-ATOM-041. -/
theorem finiteUnfoldingModelSoundness
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {context : TypedSlotContext.{u, v} Ty} {output : Ty}
    {left right : L.Term context output}
    (certificate : TypedEquationalCertificate L left right)
    (model : TypedModel.{u, v, w, x, y} L)
    (environment : model.Environment context) :
    model.evaluate left environment = model.evaluate right environment :=
  typedCertificateSemanticSoundness model certificate environment

/-- TSG-ATOM-042. -/
theorem commonContextWeakeningSoundness
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    {context ambient : TypedSlotContext.{u, v} Ty} {output : Ty}
    {left right : L.Term context output}
    (certificate : TypedEquationalCertificate L left right)
    (leftEmbedding rightEmbedding : TypedSlotEmbedding context ambient)
    (agree : leftEmbedding = rightEmbedding) :
    TypedEquationalCertificate L
      (L.rename leftEmbedding left) (L.rename rightEmbedding right) := by
  cases agree
  exact .transport leftEmbedding certificate

end TypedSlottedEGraphsPaper.AtomicLedger
