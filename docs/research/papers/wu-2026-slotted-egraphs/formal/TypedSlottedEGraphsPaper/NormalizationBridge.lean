import TypedSlottedEGraphsPaper.FiniteNormalization
import TypedSlottedEGraphsPaper.ContextGraph
import TypedSlottedEGraphsPaper.StructuralSemantics

namespace TypedSlottedEGraphsPaper

namespace NormalizationBridge

universe u v w x y z r s t

/-! ## A finite quotient normalizer generated independently of its normal form

The relation below is generated before any normalizer is defined.  In
particular, there is no constructor whose premise or conclusion mentions a
canonical representative.
-/

/-- Reflexive, symmetric, transitive closure of one local structural step. -/
inductive GeneratedEquivalence {X : Type u} (generator : X → X → Prop) :
    X → X → Prop where
  | reflexive (value : X) : GeneratedEquivalence generator value value
  | generator (step : generator left right) :
      GeneratedEquivalence generator left right
  | symmetric (derivation : GeneratedEquivalence generator left right) :
      GeneratedEquivalence generator right left
  | transitive (leftDerivation : GeneratedEquivalence generator left middle)
      (rightDerivation : GeneratedEquivalence generator middle right) :
      GeneratedEquivalence generator left right

namespace GeneratedEquivalence

/-- Equality-valued observations preserved by every local generator are
preserved by the entire independently generated equivalence. -/
theorem preservesObservation {X : Type u} {Observation : Type v}
    {generator : X → X → Prop} (observe : X → Observation)
    (localInvariant : ∀ {left right}, generator left right →
      observe left = observe right)
    {left right : X} (derivation : GeneratedEquivalence generator left right) :
    observe left = observe right := by
  induction derivation with
  | reflexive value => rfl
  | generator step => exact localInvariant step
  | symmetric derivation inductionHypothesis =>
      exact inductionHypothesis.symm
  | transitive leftDerivation rightDerivation leftIH rightIH =>
      exact leftIH.trans rightIH

end GeneratedEquivalence

/-- Finite data for normalization of an independently generated structural
equivalence.  `carrierComplete` is an explicit finiteness witness for the
ambient carrier; `relationDecidable` is an algorithm for the generated
relation, not an equality test on normal forms. -/
structure AmbientQuotientPresentation
    (X : Type u) (Support : Type v) (Schema : Type w)
    (LeafTypes : Type x) (Output : Type y)
    [Std.LinearOrderPackage X] where
  generator : X → X → Prop
  relationDecidable : DecidableRel (GeneratedEquivalence generator)
  carrier : List X
  carrierComplete : ∀ value, value ∈ carrier
  support : X → Support
  supportLocal : ∀ {left right}, generator left right →
    support left = support right
  schema : X → Schema
  schemaLocal : ∀ {left right}, generator left right →
    schema left = schema right
  leafTypes : X → LeafTypes
  leafTypesLocal : ∀ {left right}, generator left right →
    leafTypes left = leafTypes right
  output : X → Output
  outputLocal : ∀ {left right}, generator left right →
    output left = output right

namespace AmbientQuotientPresentation

variable {X : Type u} {Support : Type v} {Schema : Type w}
  {LeafTypes : Type x} {Output : Type y} [Std.LinearOrderPackage X]

/-- Identity-indexed graph-relative structure, generated without reference to
the quotient normalizer. -/
abbrev Related
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output) :=
  GeneratedEquivalence P.generator

/-- The explicitly enumerated finite orbit of `value`. -/
def orbit (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    (value : X) : List X :=
  letI : DecidableRel P.Related := P.relationDecidable
  P.carrier.filter (fun candidate => decide (P.Related value candidate))

theorem orbit_self
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    (value : X) : value ∈ P.orbit value := by
  letI : DecidableRel P.Related := P.relationDecidable
  simp only [orbit, List.mem_filter]
  exact ⟨P.carrierComplete value,
    decide_eq_true_eq.mpr (GeneratedEquivalence.reflexive value)⟩

theorem orbit_complete
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    {left right : X} (related : P.Related left right) :
    right ∈ P.orbit left := by
  letI : DecidableRel P.Related := P.relationDecidable
  simp only [orbit, List.mem_filter]
  exact ⟨P.carrierComplete right, decide_eq_true_eq.mpr related⟩

theorem orbit_invariant
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    {left right : X} (related : P.Related left right) :
    P.orbit left = P.orbit right := by
  letI : DecidableRel P.Related := P.relationDecidable
  apply List.filter_congr
  intro candidate candidateInCarrier
  apply Bool.eq_iff_iff.mpr
  simp only [decide_eq_true_eq]
  constructor
  · intro leftCandidate
    exact GeneratedEquivalence.transitive
      (GeneratedEquivalence.symmetric related) leftCandidate
  · intro rightCandidate
    exact GeneratedEquivalence.transitive related rightCandidate

/-- The finite-orbit presentation consumed by the generic least-member
normalizer. -/
def finitePresentation
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output) :
    FiniteNormalization.Presentation X where
  relation := P.Related
  relationDecidable := P.relationDecidable
  orbit := P.orbit
  orbitSelf := P.orbit_self
  orbitComplete := P.orbit_complete
  orbitInvariant := P.orbit_invariant
  relationRefl := GeneratedEquivalence.reflexive
  relationSymm := GeneratedEquivalence.symmetric
  relationTrans := GeneratedEquivalence.transitive

/-- F16/TSG-DEF-012 abstract kernel: the least member of the complete finite
orbit generated by the local structural rules. -/
def quotientNormal
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    (value : X) : X :=
  P.finitePresentation.normal value

/-- TSG-ATOM-020: quotient normalization is sound for the independently
generated structural relation. -/
theorem quotientNormal_sound
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    (value : X) : P.Related (P.quotientNormal value) value := by
  exact GeneratedEquivalence.symmetric
    (P.finitePresentation.normal_sound value)

/-- TSG-ATOM-021: equality of least finite-orbit representatives is exactly
the independently generated structural relation. -/
theorem quotientNormal_eq_iff
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    (left right : X) :
    P.quotientNormal left = P.quotientNormal right ↔ P.Related left right := by
  exact P.finitePresentation.normal_eq_normal_iff left right

/-- The full generated relation preserves support because this is required
only of each local structural rule. -/
theorem related_preserves_support
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    {left right : X} (related : P.Related left right) :
    P.support left = P.support right :=
  GeneratedEquivalence.preservesObservation P.support P.supportLocal related

/-- TSG-ATOM-022: quotient normalization preserves exact ambient support. -/
theorem quotientNormal_preserves_support
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    (value : X) :
    P.support (P.quotientNormal value) = P.support value :=
  P.related_preserves_support (P.quotientNormal_sound value)

theorem related_preserves_schema
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    {left right : X} (related : P.Related left right) :
    P.schema left = P.schema right :=
  GeneratedEquivalence.preservesObservation P.schema P.schemaLocal related

theorem related_preserves_leafTypes
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    {left right : X} (related : P.Related left right) :
    P.leafTypes left = P.leafTypes right :=
  GeneratedEquivalence.preservesObservation P.leafTypes P.leafTypesLocal related

theorem related_preserves_output
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    {left right : X} (related : P.Related left right) :
    P.output left = P.output right :=
  GeneratedEquivalence.preservesObservation P.output P.outputLocal related

/-- TSG-ATOM-023: schema, every recorded leaf type, and output type are
preserved by quotient normalization. -/
theorem quotientNormal_preserves_schema_leafTypes_output
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    (value : X) :
    P.schema (P.quotientNormal value) = P.schema value ∧
    P.leafTypes (P.quotientNormal value) = P.leafTypes value ∧
    P.output (P.quotientNormal value) = P.output value := by
  have sound := P.quotientNormal_sound value
  exact ⟨P.related_preserves_schema sound,
    P.related_preserves_leafTypes sound,
    P.related_preserves_output sound⟩

/-- TSG-ATOM-024: the same soundness, exactness, and support package applies
when the carrier is the leader-normalized node carrier rather than a port
carrier.  Intrinsic typing is represented by the observation fields. -/
theorem nodeQuotientNormal_sound_exact_support
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    (left right : X) :
    P.Related (P.quotientNormal left) left ∧
    (P.quotientNormal left = P.quotientNormal right ↔ P.Related left right) ∧
    P.support (P.quotientNormal left) = P.support left :=
  ⟨P.quotientNormal_sound left, P.quotientNormal_eq_iff left right,
    P.quotientNormal_preserves_support left⟩

/-- TSG-ATOM-025: least-member finite-orbit normalization is idempotent. -/
theorem quotientNormal_idempotent
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    (value : X) :
    P.quotientNormal (P.quotientNormal value) = P.quotientNormal value :=
  P.finitePresentation.normal_idempotent value

/-- TSG-LEM-006/F16: the complete abstract quotient-normal-form contract.
Every conclusion is derived from the local generator laws and complete finite
orbit enumeration; no field of `AmbientQuotientPresentation` states any of
these conclusions. -/
theorem ambientQuotientNormalFormExactness
    (P : AmbientQuotientPresentation X Support Schema LeafTypes Output)
    (left right : X) :
    P.Related (P.quotientNormal left) left ∧
    (P.quotientNormal left = P.quotientNormal right ↔ P.Related left right) ∧
    P.support (P.quotientNormal left) = P.support left ∧
    P.schema (P.quotientNormal left) = P.schema left ∧
    P.leafTypes (P.quotientNormal left) = P.leafTypes left ∧
    P.output (P.quotientNormal left) = P.output left ∧
    P.quotientNormal (P.quotientNormal left) = P.quotientNormal left := by
  rcases P.quotientNormal_preserves_schema_leafTypes_output left with
    ⟨schema, leafTypes, output⟩
  exact ⟨P.quotientNormal_sound left,
    P.quotientNormal_eq_iff left right,
    P.quotientNormal_preserves_support left,
    schema, leafTypes, output, P.quotientNormal_idempotent left⟩

end AmbientQuotientPresentation

/-! ## Typed-renaming-indexed structural generators

This second layer records the typed renaming carried by each local structural
step and composes those witnesses through the generated equivalence.  The
adapter at the end of the file instantiates local steps with the independent
`StructuralDerivation` calculus.
-/

/-- The operations needed to compose typed context renamings. -/
structure TypedRenamingInterface (Context : Type u) where
  Renaming : Context → Context → Type v
  identity : (context : Context) → Renaming context context
  inverse : {source target : Context} →
    Renaming source target → Renaming target source
  compose : {source middle target : Context} →
    Renaming middle target → Renaming source middle → Renaming source target

/-- A proof-relevant local structural generator indexed by its typed
renaming. -/
structure TypedStructuralGenerator (Kernel : Type u) (Context : Type v) where
  context : Kernel → Context
  renamingOps : TypedRenamingInterface.{v, w} Context
  Local : {left right : Kernel} →
    renamingOps.Renaming (context left) (context right) → Prop

namespace TypedStructuralGenerator

variable {Kernel : Type u} {Context : Type v}

/-- The unindexed local relation used to enumerate finite structural orbits. -/
def Raw (S : TypedStructuralGenerator.{u, v, w} Kernel Context)
    (left right : Kernel) : Prop :=
  ∃ alignment : S.renamingOps.Renaming (S.context left) (S.context right),
    S.Local alignment

/-- Proof-relevant closure retaining the composed typed renaming witness. -/
inductive Derivation (S : TypedStructuralGenerator.{u, v, w} Kernel Context) :
    {left right : Kernel} →
    S.renamingOps.Renaming (S.context left) (S.context right) → Type (max u v w) where
  | reflexive (value : Kernel) :
      Derivation S (S.renamingOps.identity (S.context value))
  | generator {left right : Kernel}
      {alignment : S.renamingOps.Renaming (S.context left) (S.context right)}
      (step : S.Local alignment) : Derivation S alignment
  | symmetric {left right : Kernel}
      {alignment : S.renamingOps.Renaming (S.context left) (S.context right)}
      (derivation : Derivation S alignment) :
      Derivation S (S.renamingOps.inverse alignment)
  | transitive {left middle right : Kernel}
      {leftAlignment : S.renamingOps.Renaming (S.context left) (S.context middle)}
      {rightAlignment : S.renamingOps.Renaming (S.context middle) (S.context right)}
      (leftDerivation : Derivation S leftAlignment)
      (rightDerivation : Derivation S rightAlignment) :
      Derivation S (S.renamingOps.compose rightAlignment leftAlignment)

/-- The generated relation used by normalization. -/
abbrev Related (S : TypedStructuralGenerator.{u, v, w} Kernel Context) :=
  GeneratedEquivalence S.Raw

/-- Every unindexed generated derivation has an explicit composed typed
renaming witness. -/
theorem related_iff_exists_typed_derivation
    (S : TypedStructuralGenerator.{u, v, w} Kernel Context)
    (left right : Kernel) :
    S.Related left right ↔
      ∃ alignment : S.renamingOps.Renaming (S.context left) (S.context right),
        Nonempty (S.Derivation alignment) := by
  constructor
  · intro related
    induction related with
    | reflexive value =>
        exact ⟨S.renamingOps.identity (S.context value),
          ⟨Derivation.reflexive value⟩⟩
    | generator step =>
        rcases step with ⟨alignment, localStep⟩
        exact ⟨alignment, ⟨Derivation.generator localStep⟩⟩
    | symmetric derivation inductionHypothesis =>
        rcases inductionHypothesis with ⟨alignment, ⟨typed⟩⟩
        exact ⟨S.renamingOps.inverse alignment,
          ⟨Derivation.symmetric typed⟩⟩
    | transitive leftDerivation rightDerivation leftIH rightIH =>
        rcases leftIH with ⟨leftAlignment, ⟨leftTyped⟩⟩
        rcases rightIH with ⟨rightAlignment, ⟨rightTyped⟩⟩
        exact ⟨S.renamingOps.compose rightAlignment leftAlignment,
          ⟨Derivation.transitive leftTyped rightTyped⟩⟩
  · rintro ⟨alignment, ⟨derivation⟩⟩
    induction derivation with
    | reflexive value => exact GeneratedEquivalence.reflexive value
    | generator step => exact GeneratedEquivalence.generator ⟨_, step⟩
    | symmetric derivation inductionHypothesis =>
        exact GeneratedEquivalence.symmetric inductionHypothesis
    | transitive leftDerivation rightDerivation leftIH rightIH =>
        exact GeneratedEquivalence.transitive leftIH rightIH

/-- A local invariant lifts through the renaming-indexed structural closure. -/
theorem related_preserves_observation
    (S : TypedStructuralGenerator.{u, v, w} Kernel Context)
    {Observation : Type x} (observe : Kernel → Observation)
    (localInvariant : ∀ {left right}
      {alignment : S.renamingOps.Renaming (S.context left) (S.context right)},
      S.Local alignment → observe left = observe right)
    {left right : Kernel} (related : S.Related left right) :
    observe left = observe right := by
  exact GeneratedEquivalence.preservesObservation
    (generator := S.Raw) observe
    (fun {left right} raw => by
      rcases raw with ⟨alignment, step⟩
      exact localInvariant step)
    related

end TypedStructuralGenerator

/-- A finite quotient presentation whose local rules carry actual typed
renaming witnesses.  As above, only local observation preservation is stored;
all normal-form conclusions are derived. -/
structure StructuralQuotientPresentation
    (Kernel : Type u) (Context : Type v) (Support : Type w)
    (Schema : Type x) (LeafTypes : Type y) (Output : Type z)
    [Std.LinearOrderPackage Kernel] where
  structural : TypedStructuralGenerator.{u, v, r} Kernel Context
  relationDecidable : DecidableRel structural.Related
  carrier : List Kernel
  carrierComplete : ∀ kernel, kernel ∈ carrier
  support : Kernel → Support
  supportLocal : ∀ {left right}
    {alignment : structural.renamingOps.Renaming
      (structural.context left) (structural.context right)},
    structural.Local alignment → support left = support right
  schema : Kernel → Schema
  schemaLocal : ∀ {left right}
    {alignment : structural.renamingOps.Renaming
      (structural.context left) (structural.context right)},
    structural.Local alignment → schema left = schema right
  leafTypes : Kernel → LeafTypes
  leafTypesLocal : ∀ {left right}
    {alignment : structural.renamingOps.Renaming
      (structural.context left) (structural.context right)},
    structural.Local alignment → leafTypes left = leafTypes right
  output : Kernel → Output
  outputLocal : ∀ {left right}
    {alignment : structural.renamingOps.Renaming
      (structural.context left) (structural.context right)},
    structural.Local alignment → output left = output right

namespace StructuralQuotientPresentation

variable {Kernel : Type u} {Context : Type v} {Support : Type w}
  {Schema : Type x} {LeafTypes : Type y} {Output : Type z}
  [Std.LinearOrderPackage Kernel]

/-- Forget only the explicit renaming index, retaining its existence in the
raw generator.  This is the exact finite-orbit presentation used by `Q`. -/
def asAmbient
    (P : StructuralQuotientPresentation Kernel Context Support Schema
      LeafTypes Output) :
    AmbientQuotientPresentation Kernel Support Schema LeafTypes Output where
  generator := P.structural.Raw
  relationDecidable := P.relationDecidable
  carrier := P.carrier
  carrierComplete := P.carrierComplete
  support := P.support
  supportLocal := by
    intro left right raw
    rcases raw with ⟨alignment, step⟩
    exact P.supportLocal step
  schema := P.schema
  schemaLocal := by
    intro left right raw
    rcases raw with ⟨alignment, step⟩
    exact P.schemaLocal step
  leafTypes := P.leafTypes
  leafTypesLocal := by
    intro left right raw
    rcases raw with ⟨alignment, step⟩
    exact P.leafTypesLocal step
  output := P.output
  outputLocal := by
    intro left right raw
    rcases raw with ⟨alignment, step⟩
    exact P.outputLocal step

/-- Least representative of a complete finite orbit of typed structural
renamings. -/
def quotientNormal
    (P : StructuralQuotientPresentation Kernel Context Support Schema
      LeafTypes Output) (kernel : Kernel) : Kernel :=
  P.asAmbient.quotientNormal kernel

/-- The structural presentation's generated relation. -/
abbrev Related
    (P : StructuralQuotientPresentation Kernel Context Support Schema
      LeafTypes Output) := P.structural.Related

theorem quotientNormal_sound
    (P : StructuralQuotientPresentation Kernel Context Support Schema
      LeafTypes Output) (kernel : Kernel) :
    P.Related (P.quotientNormal kernel) kernel :=
  P.asAmbient.quotientNormal_sound kernel

/-- Equality of canonical kernels iff there is a composed typed renaming and
a proof-relevant structural derivation carrying it. -/
theorem quotientNormal_eq_iff_typedDerivation
    (P : StructuralQuotientPresentation Kernel Context Support Schema
      LeafTypes Output) (left right : Kernel) :
    P.quotientNormal left = P.quotientNormal right ↔
      ∃ alignment : P.structural.renamingOps.Renaming
        (P.structural.context left) (P.structural.context right),
        Nonempty (P.structural.Derivation alignment) := by
  exact (P.asAmbient.quotientNormal_eq_iff left right).trans
    (P.structural.related_iff_exists_typed_derivation left right)

theorem quotientNormal_preserves_support
    (P : StructuralQuotientPresentation Kernel Context Support Schema
      LeafTypes Output) (kernel : Kernel) :
    P.support (P.quotientNormal kernel) = P.support kernel :=
  P.asAmbient.quotientNormal_preserves_support kernel

theorem quotientNormal_preserves_schema_leafTypes_output
    (P : StructuralQuotientPresentation Kernel Context Support Schema
      LeafTypes Output) (kernel : Kernel) :
    P.schema (P.quotientNormal kernel) = P.schema kernel ∧
    P.leafTypes (P.quotientNormal kernel) = P.leafTypes kernel ∧
    P.output (P.quotientNormal kernel) = P.output kernel :=
  P.asAmbient.quotientNormal_preserves_schema_leafTypes_output kernel

theorem quotientNormal_idempotent
    (P : StructuralQuotientPresentation Kernel Context Support Schema
      LeafTypes Output) (kernel : Kernel) :
    P.quotientNormal (P.quotientNormal kernel) = P.quotientNormal kernel :=
  P.asAmbient.quotientNormal_idempotent kernel

end StructuralQuotientPresentation

/-! ## Direct adapter to the structural calculus -/

/-- The abstract renaming interface instantiated by the paper's concrete
typed-slot bijections. -/
def typedSlotRenamingInterface {Ty : Type u} :
    TypedRenamingInterface
      (TypedSlotContext.{u, v} Ty) where
  Renaming := TypedSlotRenaming
  identity := TypedSlotRenaming.id
  inverse := TypedSlotRenaming.symm
  compose := TypedSlotRenaming.comp

/-- A complete structurally typed kernel with a possibly different finite
outer context.  The bound scope and output type remain intrinsic indices. -/
structure PackagedStructuralKernel
    {Ty : Type u} {Block : Type x} {Operator : Ty → Type y}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (D : IndexedStructuralAlphaDefinition.{u, v, w, x, y, z, r}
      Block Operator L)
    (bound : List Ty) (output : Ty) where
  context : TypedSlotContext.{u, v} Ty
  value : D.Syntax context bound output

/-- A `StructuralDerivation` under a typed outer-context renaming is one
independent local generator for effective-kernel equivalence.  Symmetry and
transitivity are supplied only by `GeneratedEquivalence`, not by normal-form
equality. -/
def structuralSyntaxGenerator
    {Ty : Type u} {Block : Type x} {Operator : Ty → Type y}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (D : IndexedStructuralAlphaDefinition.{u, v, w, x, y, z, r}
      Block Operator L)
    (bound : List Ty) (output : Ty) :
    TypedStructuralGenerator
      (PackagedStructuralKernel D bound output)
      (TypedSlotContext.{u, v} Ty) where
  context := PackagedStructuralKernel.context
  renamingOps := typedSlotRenamingInterface
  Local := fun {left right} alignment =>
    Nonempty (D.Derivation alignment.toTypedSlotEmbedding
      left.value right.value)

/-- Fixed-ambient, identity-indexed structural generator used by F16. -/
def identityStructuralGenerator
    {Ty : Type u} {Block : Type x} {Operator : Ty → Type y}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (D : IndexedStructuralAlphaDefinition.{u, v, w, x, y, z, r}
      Block Operator L)
    (context : TypedSlotContext.{u, v} Ty) (bound : List Ty) (output : Ty)
    (left right : D.Syntax context bound output) : Prop :=
  Nonempty (D.Derivation
    (TypedSlotEmbedding.id context) left right)

/-! ## Effective-support canonical records -/

/-- Context embeddings and their composition with a typed renaming.  In the
concrete graph model this is `TypedSlotEmbedding`, while the renaming is a
bijective `TypedSlotRenaming`. -/
structure ContextEmbeddingInterface
    {Context : Type u} (R : TypedRenamingInterface.{u, v} Context) where
  Embedding : Context → Context → Type w
  ofRenaming : {source target : Context} →
    R.Renaming source target → Embedding source target
  compose : {source middle target : Context} →
    Embedding middle target → Embedding source middle →
      Embedding source target

/-- The concrete embedding interface from the finite typed contexts used by
`ContextGraph`. -/
def typedSlotEmbeddingInterface {Ty : Type u} :
    ContextEmbeddingInterface (typedSlotRenamingInterface
      (Ty := Ty)) where
  Embedding := TypedSlotEmbedding
  ofRenaming := TypedSlotRenaming.toTypedSlotEmbedding
  compose := TypedSlotEmbedding.comp

/-- A constructive extractor for the proof-relevant typed witness carried by
the generated relation.  This is separate from the normalizer: an executable
instance must provide it from its checked derivation datatype, rather than
using classical choice. -/
structure ConstructiveWitnessSelector
    {Kernel : Type u} {Context : Type v}
    (S : TypedStructuralGenerator.{u, v, w} Kernel Context) where
  select : ∀ {left right : Kernel}, S.Related left right →
    Sigma fun alignment : S.renamingOps.Renaming
      (S.context left) (S.context right) =>
      S.Derivation alignment

/-- F17/TSG-DEF-013 abstract candidate and record environment.  The finite
structural presentation supplies every orbit candidate; `selectWitness`
extracts a checked typed witness constructively.  Kernel-to-ambient inclusion
and provenance remain distinct from that bijective witness. -/
structure EffectiveSupportCanonicalizer
    (Node : Type u) (Kernel : Type v) (Context : Type w)
    (Support : Type x) (Schema : Type y) (LeafTypes : Type z)
    (Output : Type r) (Provenance : Type s)
    [Std.LinearOrderPackage Kernel] where
  quotient : StructuralQuotientPresentation.{v, w, x, y, z, r, t}
    Kernel Context Support Schema LeafTypes Output
  selectWitness : ConstructiveWitnessSelector quotient.structural
  embeddingOps : ContextEmbeddingInterface.{w, t, t}
    quotient.structural.renamingOps
  ambientContext : Node → Context
  kernel : Node → Kernel
  effectiveSupport : Node → Support
  nodeSchema : Node → Schema
  nodeLeafTypes : Node → LeafTypes
  nodeOutput : Node → Output
  kernelSupport : ∀ node,
    quotient.support (kernel node) = effectiveSupport node
  kernelSchema : ∀ node,
    quotient.schema (kernel node) = nodeSchema node
  kernelLeafTypes : ∀ node,
    quotient.leafTypes (kernel node) = nodeLeafTypes node
  kernelOutput : ∀ node,
    quotient.output (kernel node) = nodeOutput node
  inclusion : ∀ node, embeddingOps.Embedding
    (quotient.structural.context (kernel node)) (ambientContext node)
  provenance : Node → Provenance

namespace EffectiveSupportCanonicalizer

variable {Node : Type u} {Kernel : Type v} {Context : Type w}
  {Support : Type x} {Schema : Type y} {LeafTypes : Type z}
  {Output : Type r} {Provenance : Type s}
  [Std.LinearOrderPackage Kernel]

/-- The least structural representative of the node's exact effective
leader kernel. -/
def canonicalShape
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (node : Node) : Kernel :=
  C.quotient.quotientNormal (C.kernel node)

/-- The data retained by canonicalization.  The shape witness is a typed
bijection with a proof-relevant structural derivation.  Ambient transport is
computed by composing the generally nonsurjective inclusion with that
witness; no inverse of the ambient transport is present. -/
structure CanonicalRecord
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (node : Node) where
  shapeWitness :
    Sigma fun alignment : C.quotient.structural.renamingOps.Renaming
      (C.quotient.structural.context (C.canonicalShape node))
      (C.quotient.structural.context (C.kernel node)) =>
      C.quotient.structural.Derivation alignment
  ambientTransport : C.embeddingOps.Embedding
    (C.quotient.structural.context (C.canonicalShape node))
    (C.ambientContext node)
  ambientTransportEquation :
    ambientTransport = C.embeddingOps.compose (C.inclusion node)
      (C.embeddingOps.ofRenaming shapeWitness.1)
  provenance : Provenance

/-- Construct the theorem-facing canonical record without classical choice.
The explicit selector is part of the executable presentation. -/
def canonicalRecord
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (node : Node) : C.CanonicalRecord node :=
  let witness := C.selectWitness.select
    (C.quotient.quotientNormal_sound (C.kernel node))
  { shapeWitness := witness
    ambientTransport := C.embeddingOps.compose (C.inclusion node)
      (C.embeddingOps.ofRenaming witness.1)
    ambientTransportEquation := rfl
    provenance := C.provenance node }

/-- The record's typed renaming and structural derivation relate the returned
shape to the effective leader kernel. -/
theorem canonicalRecord_has_typed_shapeWitness
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (node : Node) :
    Nonempty (C.quotient.structural.Derivation
      (C.canonicalRecord node).shapeWitness.1) :=
  ⟨(C.canonicalRecord node).shapeWitness.2⟩

/-- The canonical shape has the node's exact effective support. -/
theorem canonicalRecord_exact_effectiveSupport
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (node : Node) :
    C.quotient.support (C.canonicalShape node) = C.effectiveSupport node := by
  exact (C.quotient.quotientNormal_preserves_support (C.kernel node)).trans
    (C.kernelSupport node)

/-- The canonical shape preserves schema, every recorded leaf type, and the
intrinsic node output type. -/
theorem canonicalRecord_preserves_schema_leafTypes_output
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (node : Node) :
    C.quotient.schema (C.canonicalShape node) = C.nodeSchema node ∧
    C.quotient.leafTypes (C.canonicalShape node) = C.nodeLeafTypes node ∧
    C.quotient.output (C.canonicalShape node) = C.nodeOutput node := by
  rcases C.quotient.quotientNormal_preserves_schema_leafTypes_output
      (C.kernel node) with ⟨schema, leafTypes, output⟩
  exact ⟨schema.trans (C.kernelSchema node),
    leafTypes.trans (C.kernelLeafTypes node),
    output.trans (C.kernelOutput node)⟩

/-- The record never confuses its shape witness with ambient transport: the
latter is definitionally the inclusion after the typed witness. -/
theorem canonicalRecord_ambientTransport_composes
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (node : Node) :
    (C.canonicalRecord node).ambientTransport =
      C.embeddingOps.compose (C.inclusion node)
        (C.embeddingOps.ofRenaming
          (C.canonicalRecord node).shapeWitness.1) :=
  (C.canonicalRecord node).ambientTransportEquation

/-- TSG-INV-005: all theorem-facing postconditions of the returned record are
derived from the finite structural presentation, the exact kernel extraction
observations, and typed composition. -/
theorem canonicalRecordPostconditions
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (node : Node) :
    Nonempty (C.quotient.structural.Derivation
      (C.canonicalRecord node).shapeWitness.1) ∧
    C.quotient.support (C.canonicalShape node) = C.effectiveSupport node ∧
    C.quotient.schema (C.canonicalShape node) = C.nodeSchema node ∧
    C.quotient.leafTypes (C.canonicalShape node) = C.nodeLeafTypes node ∧
    C.quotient.output (C.canonicalShape node) = C.nodeOutput node ∧
    (C.canonicalRecord node).ambientTransport =
      C.embeddingOps.compose (C.inclusion node)
        (C.embeddingOps.ofRenaming
          (C.canonicalRecord node).shapeWitness.1) := by
  rcases C.canonicalRecord_preserves_schema_leafTypes_output node with
    ⟨schema, leafTypes, output⟩
  exact ⟨C.canonicalRecord_has_typed_shapeWitness node,
    C.canonicalRecord_exact_effectiveSupport node,
    schema, leafTypes, output,
    C.canonicalRecord_ambientTransport_composes node⟩

/-- TSG-ATOM-026: canonical shape equality is equivalent to a typed renaming
carrying an independently generated structural derivation between the two
effective kernels.  Only effective-kernel contexts occur in the witness. -/
theorem canonicalShape_eq_iff_effectiveKernel_typedRenaming
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (left right : Node) :
    C.canonicalShape left = C.canonicalShape right ↔
      ∃ alignment : C.quotient.structural.renamingOps.Renaming
        (C.quotient.structural.context (C.kernel left))
        (C.quotient.structural.context (C.kernel right)),
        Nonempty (C.quotient.structural.Derivation alignment) :=
  C.quotient.quotientNormal_eq_iff_typedDerivation
    (C.kernel left) (C.kernel right)

/-- Either direction of shape exactness entails equal node output types. -/
theorem canonicalShape_exactness_preserves_output
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (left right : Node)
    (eitherSide :
      C.canonicalShape left = C.canonicalShape right ∨
      (∃ alignment : C.quotient.structural.renamingOps.Renaming
        (C.quotient.structural.context (C.kernel left))
        (C.quotient.structural.context (C.kernel right)),
        Nonempty (C.quotient.structural.Derivation alignment))) :
    C.nodeOutput left = C.nodeOutput right := by
  have typed :
      ∃ alignment : C.quotient.structural.renamingOps.Renaming
        (C.quotient.structural.context (C.kernel left))
        (C.quotient.structural.context (C.kernel right)),
        Nonempty (C.quotient.structural.Derivation alignment) := by
    rcases eitherSide with shapeEquality | relation
    · exact (C.canonicalShape_eq_iff_effectiveKernel_typedRenaming
        left right).mp shapeEquality
    · exact relation
  have related : C.quotient.Related (C.kernel left) (C.kernel right) :=
    (C.quotient.structural.related_iff_exists_typed_derivation
      (C.kernel left) (C.kernel right)).mpr typed
  have outputEquality := C.quotient.asAmbient.related_preserves_output related
  exact (C.kernelOutput left).symm.trans
    (outputEquality.trans (C.kernelOutput right))

/-- TSG-COR-003/F17: effective-support canonical-shape exactness and the
output consequence, stated without any renaming between the larger ambient
input contexts. -/
theorem effectiveSupportCanonicalShapeExactness
    (C : EffectiveSupportCanonicalizer Node Kernel Context Support Schema
      LeafTypes Output Provenance) (left right : Node) :
    (C.canonicalShape left = C.canonicalShape right ↔
      ∃ alignment : C.quotient.structural.renamingOps.Renaming
        (C.quotient.structural.context (C.kernel left))
        (C.quotient.structural.context (C.kernel right)),
        Nonempty (C.quotient.structural.Derivation alignment)) ∧
    (C.canonicalShape left = C.canonicalShape right →
      C.nodeOutput left = C.nodeOutput right) ∧
    ((∃ alignment : C.quotient.structural.renamingOps.Renaming
        (C.quotient.structural.context (C.kernel left))
        (C.quotient.structural.context (C.kernel right)),
        Nonempty (C.quotient.structural.Derivation alignment)) →
      C.nodeOutput left = C.nodeOutput right) := by
  refine ⟨C.canonicalShape_eq_iff_effectiveKernel_typedRenaming left right,
    ?_, ?_⟩
  · intro equality
    exact C.canonicalShape_exactness_preserves_output left right (Or.inl equality)
  · intro relation
    exact C.canonicalShape_exactness_preserves_output left right (Or.inr relation)

end EffectiveSupportCanonicalizer

end NormalizationBridge

end TypedSlottedEGraphsPaper
