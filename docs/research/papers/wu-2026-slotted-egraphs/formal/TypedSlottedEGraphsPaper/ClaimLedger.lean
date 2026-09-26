import TypedSlottedEGraphsPaper.ContextGraph
import TypedSlottedEGraphsPaper.Certificates
import TypedSlottedEGraphsPaper.ProfileRules
import TypedSlottedEGraphsPaper.AtomicLedger

namespace TypedSlottedEGraphsPaper.ClaimLedger

universe u v w x y z q

/-! The declarations in this file fill formal-unit gaps that are not theorem
wrappers.  Each is an explicit specification carrier used by the compressed
paper; neither declaration asserts a proof result. -/

/-- The concrete embedding action bundled at the two public syntax levels.
Bound de Bruijn indices remain internal to `ConcretePort.act`; both functions
transport only the free-context index. -/
structure ConcreteEmbeddingActionBundle
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    (source target : TypedSlotContext.{u, v} Ty)
    (embedding : TypedSlotEmbedding source target) where
  port : {bound : List Ty} -> {schema : PortSchema Ty Descriptor} ->
    ConcretePort signature source bound schema ->
      ConcretePort signature target bound schema
  node : {output : Ty} ->
    ConcreteFlexibleArityENode signature source output ->
      ConcreteFlexibleArityENode signature target output

/-- TSG-DEF-005: the actual recursive free-context action on concrete ports
and heterogeneous nodes. -/
def TSGDEF005ConcreteEmbeddingActionBundle
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) :
    ConcreteEmbeddingActionBundle signature source target embedding where
  port := ConcretePort.act embedding
  node := ConcreteFlexibleArityENode.act embedding

/-- TSG-ALG-003: the checked mathematical collision gate is precisely an
obligation-composition recipe, not a hash-table or union implementation. -/
abbrev TSGALG003CompatibilityGatedCollisionContract
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    (source target : TheoremTraceState.{u, v, w, x} L) :=
  ObligationComposition source target

/-- TSG-ALG-004: the checked rebuild boundary classifies each final
obligation as inherited or justified by one local certificate. -/
abbrev TSGALG004CertificatePreservingRebuildContract
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    (source target : TheoremTraceState.{u, v, w, x} L) :=
  ObligationAddition source target

/-- TSG-DEF-006: an intrinsically typed node over the canonical representative
of a finite free context.  Binder coordinates remain the typed de Bruijn
coordinates of `ConcretePort`; sequence, bag, and set tags retain their finite
occurrence vectors in that syntax. -/
structure TSGDEF006TypedShapeCarrier
    {Ty : Type u} (alphabet : OrderedCountableTypeAlphabet Ty)
    {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, 0, w, x, y}
      Ty Descriptor ClassId Op)
    (output : Ty) where
  sourceContext : FiniteTypedContext Ty
  node : ConcreteFlexibleArityENode signature
    (sourceContext.canonical alphabet).toTypedSlotContext output

/-- TSG-INV-006: descriptor admissibility is invariant under restriction of
the outer environment along a typed embedding.  The bound assignment is kept
fixed; only the caller context changes. -/
structure TSGINV006BinderAdmissibilityNaturality
    {Ty : Type u} {L : TypedTermLanguage.{u, v, w} Ty}
    (model : TypedModel.{u, v, w, x, y} L)
    (Descriptor : Type z) (BoundAssignment : Descriptor -> Type q) where
  admissible : (descriptor : Descriptor) -> BoundAssignment descriptor ->
    {context : TypedSlotContext.{u, v} Ty} ->
      model.Environment context -> Prop
  outerNatural : forall (descriptor : Descriptor)
      (assignment : BoundAssignment descriptor)
      {source target : TypedSlotContext.{u, v} Ty}
      (embedding : TypedSlotEmbedding source target)
      (environment : model.Environment target),
    admissible descriptor assignment (model.restrict embedding environment) <->
      admissible descriptor assignment environment

/-- A complete binder descriptor keeps its semantic metadata separate from
each fresh occurrence.  Its certified automorphisms form a represented group
and preserve domains, multiplicities, disjointness, and dependency order. -/
structure TSGFND006CompleteBinderDescriptor
    (Ty : Type u) (Domain : Type x) where
  context : TypedSlotContext.{u, v} Ty
  domain : context.Slot -> Domain
  multiplicity : context.Slot -> Nat
  disjoint : context.Slot -> context.Slot -> Prop
  precedes : context.Slot -> context.Slot -> Prop
  Automorphism : Type y
  identity : Automorphism
  compose : Automorphism -> Automorphism -> Automorphism
  inverse : Automorphism -> Automorphism
  action : Automorphism -> TypedSlotRenaming context context
  actionIdentity : action identity = TypedSlotRenaming.id context
  actionCompose : forall first second,
    action (compose first second) =
      TypedSlotRenaming.comp (action first) (action second)
  actionInverse : forall automorphism,
    action (inverse automorphism) =
      TypedSlotRenaming.symm (action automorphism)
  domainPreserved : forall automorphism slot,
    domain ((action automorphism).toFun slot) = domain slot
  multiplicityPreserved : forall automorphism slot,
    multiplicity ((action automorphism).toFun slot) = multiplicity slot
  disjointPreserved : forall automorphism left right,
    disjoint ((action automorphism).toFun left)
        ((action automorphism).toFun right) <->
      disjoint left right
  dependencyPreserved : forall automorphism left right,
    precedes ((action automorphism).toFun left)
        ((action automorphism).toFun right) <->
      precedes left right

/-- TSG-FND-006 as one declaration: a complete descriptor together with one
fresh caller-specific occurrence aligned to that descriptor context. -/
structure TSGFND006BinderDescriptorOccurrenceBundle
    (Ty : Type u) (Domain : Type x) (Name : Type z) where
  descriptor : TSGFND006CompleteBinderDescriptor.{u, v, x, y} Ty Domain
  caller : TypedSlotContext.{u, v} Ty
  occurrence : AtomicLedger.BinderDescriptorOccurrence.{u, z, v} Name
    descriptor.context caller

/-- TSG-ALG-002: finite candidate enumeration is extensionally complete,
and the returned record denotes the present least complete candidate.  The
collision key projects only the returned shape. -/
structure TSGALG002CompleteFiniteCanonicalizationContract
    (Input Candidate Record Shape : Type u)
    [Std.LinearOrderPackage Candidate] where
  candidates : Input -> List Candidate
  candidatesNonempty : forall input, candidates input ≠ []
  complete : Input -> Candidate -> Prop
  enumeratedComplete : forall input candidate,
    candidate ∈ candidates input -> complete input candidate
  everyCompleteEnumerated : forall input candidate,
    complete input candidate -> candidate ∈ candidates input
  selected : Input -> Candidate
  selectedPresent : forall input, selected input ∈ candidates input
  selectedLeast : forall input candidate,
    candidate ∈ candidates input -> selected input <= candidate
  canonicalize : Input -> Record
  candidateOf : Record -> Candidate
  returnedRecordExactlySelected : forall input,
    candidateOf (canonicalize input) = selected input
  shapeOf : Record -> Shape
  collisionKey : Input -> Shape
  collisionKeyOnlyShape : forall input,
    collisionKey input = shapeOf (canonicalize input)

/-- TSG-ALG-006: the displayed canonicalization pseudocode is read through a
distinct copy of the complete finite-candidate contract. -/
abbrev TSGALG006CompleteCanonPseudocodeContract
    (Input Candidate Record Shape : Type u)
    [Std.LinearOrderPackage Candidate] :=
  TSGALG002CompleteFiniteCanonicalizationContract Input Candidate Record Shape

theorem TSGALG002CompleteFiniteCanonicalizationContract.selectedComplete
    {Input Candidate Record Shape : Type u}
    [Std.LinearOrderPackage Candidate]
    (contract : TSGALG002CompleteFiniteCanonicalizationContract
      Input Candidate Record Shape)
    (input : Input) : contract.complete input (contract.selected input) :=
  contract.enumeratedComplete input (contract.selected input)
    (contract.selectedPresent input)

/-- TSG-APP-005: certified rebuilding combines termination at a quiescent
state, strict interface contraction justified by its decomposition witness,
and forward node congruence derived from pointwise port evidence. -/
theorem TSGAPP005CertifiedAbstractRebuildContract
    {State : Type u} :
    (forall (system : RebuildSystem State) (initial : State),
      exists final,
        RebuildReachable system initial final /\ system.Quiescent final) /\
    (forall (state : ProfileRules.RebuildState)
      (restriction : ProfileRules.InterfaceRestrictionCertificate state),
      (ProfileRules.commitRestriction state restriction).interfaceSize <
        state.interfaceSize) /\
    (forall {Head TypeInstantiation Port : Type v}
      {relation : Port -> Port -> Prop}
      (head : Head) (instantiation : TypeInstantiation)
      {leftPorts rightPorts : List Port},
      ProfileRules.PointwiseRelated relation leftPorts rightPorts ->
        ProfileRules.NodeCongruence relation
          ⟨head, instantiation, leftPorts⟩
          ⟨head, instantiation, rightPorts⟩) := by
  refine ⟨fun system initial => finiteRebuildQuiescence system initial, ?_, ?_⟩
  · intro state restriction
    change restriction.restrictedSize < state.interfaceSize
    have decomposition := restriction.sizeDecomposition
    omega
  · intro Head TypeInstantiation Port relation head instantiation
      leftPorts rightPorts ports
    exact ProfileRules.NodeCongruence.sameHead (R := relation)
      head instantiation ports

/-! Executable natural-number accounting used in place of asymptotic
notation.  These are accounting definitions, not growth-rate results. -/

/-- Ceiling base-two logarithm on natural sizes, with zero cost at sizes zero
and one. -/
def ceilLog2 : Nat -> Nat
  | 0 => 0
  | 1 => 0
  | n + 2 => Nat.log2 (n + 1) + 1

/-- Conservative comparison-sort work budget. -/
def structuralComputationBudget
    (inputSize pathLength canonicalWork kernelSize : Nat) : Nat :=
  inputSize * ceilLog2 (2 + inputSize) + pathLength +
    canonicalWork * kernelSize * ceilLog2 (2 + kernelSize)

/-- Auxiliary orbit workspace budget. -/
def auxiliaryKernelWorkspaceBudget (kernelSize : Nat) : Nat := kernelSize

/-- Returned structural-record budget before a separately materialized
certificate is counted. -/
def returnedStructuralRecordBudget (kernelSize pathLength : Nat) : Nat :=
  kernelSize + pathLength

end TypedSlottedEGraphsPaper.ClaimLedger
