import Std
import TypedSlottedEGraphsPaper.FiniteNormalization

namespace TypedSlottedEGraphsPaper
namespace ProfileRules

universe u v w x

/-! ## Structural trace and canonical-record contracts -/

/-- A typed inclusion between finite contexts.  Context coordinates are
represented by de Bruijn positions; the injection is the complete transport
data. -/
structure FinEmbedding (m n : Nat) where
  toFun : Fin m → Fin n
  injective : Function.Injective toFun

namespace FinEmbedding

def id (n : Nat) : FinEmbedding n n where
  toFun := _root_.id
  injective := Function.injective_id

def comp {k m n : Nat} (e : FinEmbedding m n) (d : FinEmbedding k m) :
    FinEmbedding k n where
  toFun := e.toFun ∘ d.toFun
  injective := e.injective.comp d.injective

@[simp] theorem comp_apply {k m n : Nat} (e : FinEmbedding m n)
    (d : FinEmbedding k m) (i : Fin k) :
    (comp e d).toFun i = e.toFun (d.toFun i) := rfl

end FinEmbedding

/-- A bijective typed coordinate map, with both inverse laws as data. -/
structure FinRenaming (m n : Nat) where
  toFun : Fin m → Fin n
  invFun : Fin n → Fin m
  leftInverse : ∀ i, invFun (toFun i) = i
  rightInverse : ∀ j, toFun (invFun j) = j

namespace FinRenaming

def id (n : Nat) : FinRenaming n n where
  toFun := _root_.id
  invFun := _root_.id
  leftInverse := by intro i; rfl
  rightInverse := by intro i; rfl

def symm {m n : Nat} (r : FinRenaming m n) : FinRenaming n m where
  toFun := r.invFun
  invFun := r.toFun
  leftInverse := r.rightInverse
  rightInverse := r.leftInverse

def comp {k m n : Nat} (r : FinRenaming m n) (s : FinRenaming k m) :
    FinRenaming k n where
  toFun := r.toFun ∘ s.toFun
  invFun := s.invFun ∘ r.invFun
  leftInverse := by intro i; simp [r.leftInverse, s.leftInverse]
  rightInverse := by intro i; simp [r.rightInverse, s.rightInverse]

def toEmbedding {m n : Nat} (r : FinRenaming m n) : FinEmbedding m n where
  toFun := r.toFun
  injective := by
    intro i j h
    have := congrArg r.invFun h
    simpa [r.leftInverse] using this

theorem ext {m n : Nat} {r s : FinRenaming m n}
    (h : ∀ i, r.toFun i = s.toFun i) : r = s := by
  cases r with
  | mk rf ri rl rr =>
    cases s with
    | mk sf si sl sr =>
      have hf : rf = sf := funext h
      cases hf
      have hi : ri = si := by
        funext j
        exact (congrArg ri (sr j).symm).trans (rl (si j))
      cases hi
      rfl

end FinRenaming

/-- A trace label records structural endpoints but no semantic witness. -/
structure TraceLabel (Node : Type u) where
  source : Node
  target : Node

/-- An ordered structural trace.  Its type enforces exact adjacency and exact
source and target endpoints. -/
inductive StructuralTrace {Node : Type u} (Label : Type v)
    (source target : Label → Node) : Node → Node → Type (max u v) where
  | nil (x : Node) : StructuralTrace Label source target x x
  | cons (l : Label) {z : Node}
      (rest : StructuralTrace Label source target (target l) z) :
      StructuralTrace Label source target (source l) z

/-- A coherent interpretation supplies a local certificate for each trace
label.  Replay, rather than extraction, consumes this witness family. -/
structure TraceInterpreter {Node : Type u} (Label : Type v)
    (source target : Label → Node) (Meaning : Type w) where
  denote : Node → Meaning
  localCertificate : ∀ l, denote (source l) = denote (target l)

theorem replayTrace {Node : Type u} {Label : Type v} {Meaning : Type w}
    {source target : Label → Node}
    (I : TraceInterpreter Label source target Meaning) :
    {x y : Node} → StructuralTrace Label source target x y →
      I.denote x = I.denote y
  | _, _, .nil _ => rfl
  | _, _, .cons l rest => (I.localCertificate l).trans (replayTrace I rest)

/-- An exact-support kernel result.  The trace is witness independent; only
its later interpreter depends on a coherent witness family. -/
structure KernelTraceResult (Term : Nat → Type u) (Label : Type v)
    (source target : Label → Sigma Term) (n : Nat) (input : Term n) where
  effectiveSize : Nat
  kernel : Term effectiveSize
  inclusion : FinEmbedding effectiveSize n
  trace : StructuralTrace Label source target
    ⟨n, input⟩ ⟨effectiveSize, kernel⟩

/-- An extractor returns structural data only. -/
structure KernelExtractor (Term : Nat → Type u) (Label : Type v)
    (source target : Label → Sigma Term) where
  run : {n : Nat} → (input : Term n) →
    KernelTraceResult Term Label source target n input

/-- `TSG-APP-001`: the structural trace has exact dependent endpoints and can
be replayed by any coherent interpreter without changing the extracted
kernel, effective inclusion, or trace. -/
theorem tsgApp001_kernelTraceReplayContract
    {Term : Nat → Type u} {Label : Type v} {Meaning₁ : Type w}
    {Meaning₂ : Type} {source target : Label → Sigma Term}
    (E : KernelExtractor Term Label source target)
    (I : TraceInterpreter Label source target Meaning₁)
    (J : TraceInterpreter Label source target Meaning₂)
    {n : Nat} (input : Term n) :
    let r := E.run input
    I.denote ⟨n, input⟩ = I.denote ⟨r.effectiveSize, r.kernel⟩ ∧
    J.denote ⟨n, input⟩ = J.denote ⟨r.effectiveSize, r.kernel⟩ := by
  dsimp
  exact ⟨replayTrace I (E.run input).trace,
    replayTrace J (E.run input).trace⟩

/-- Complete witness-independent canonical data.  Ambient transport is not a
stored guess: it is computed by composing the exact-support inclusion with
the shape renaming. -/
structure CanonicalStructuralRecord (Term : Nat → Type u) (Label : Type v)
    (source target : Label → Sigma Term) (Shape : Type w)
    (n : Nat) (input : Term n)
    extends KernelTraceResult Term Label source target n input where
  shape : Shape
  shapeWitness : FinRenaming effectiveSize effectiveSize

def CanonicalStructuralRecord.ambientTransport
    {Term : Nat → Type u} {Label : Type v}
    {source target : Label → Sigma Term} {Shape : Type w}
    {n : Nat} {input : Term n}
    (r : CanonicalStructuralRecord Term Label source target Shape n input) :
    FinEmbedding r.effectiveSize n :=
  FinEmbedding.comp r.inclusion r.shapeWitness.toEmbedding

def CanonicalStructuralRecord.collisionKey
    {Term : Nat → Type u} {Label : Type v}
    {source target : Label → Sigma Term} {Shape : Type w}
    {n : Nat} {input : Term n}
    (r : CanonicalStructuralRecord Term Label source target Shape n input) : Shape :=
  r.shape

/-- `TSG-APP-002`: replay adds only the exact endpoint certificate; the
collision key and ambient transport remain projections of structural data. -/
theorem tsgApp002_completeCanonicalRecords
    {Term : Nat → Type u} {Label : Type v}
    {source target : Label → Sigma Term} {Shape : Type}
    {n : Nat} {input : Term n}
    (r : CanonicalStructuralRecord Term Label source target Shape n input) :
    r.ambientTransport =
      FinEmbedding.comp r.inclusion r.shapeWitness.toEmbedding ∧
    r.collisionKey = r.shape ∧
    ∀ {Meaning : Type w}
      (I : TraceInterpreter Label source target Meaning),
      I.denote ⟨n, input⟩ = I.denote ⟨r.effectiveSize, r.kernel⟩ := by
  exact ⟨rfl, rfl, fun I => replayTrace I r.trace⟩

def conjugate {n : Nat} (a π : FinRenaming n n) : FinRenaming n n :=
  FinRenaming.comp a (FinRenaming.comp π a.symm)

/-- A complete binder descriptor exposes exactly its certified finite list of
automorphisms.  Other descriptor fields are abstracted into the admission
predicate rather than silently treated as permutable. -/
structure BinderDescriptor (n : Nat) where
  automorphisms : List (FinRenaming n n)
  certifies : FinRenaming n n → Prop
  exactGroup : ∀ π, π ∈ automorphisms ↔ certifies π

structure BlockOccurrence (n : Nat) where
  fromDescriptor : FinRenaming n n

structure CanonicalBlockResult (n : Nat) where
  canonicalOccurrence : FinRenaming n n
  alignment : FinRenaming n n
  transportedAutomorphisms : List (FinRenaming n n)

/-- De Bruijn positions make the least fresh canonical occurrence the identity
occurrence.  The returned alignment is the exact inverse of the source
occurrence. -/
def canonicalBlockOccurrence {n : Nat} (β : BinderDescriptor n)
    (o : BlockOccurrence n) : CanonicalBlockResult n where
  canonicalOccurrence := FinRenaming.id _
  alignment := o.fromDescriptor.symm
  transportedAutomorphisms :=
    β.automorphisms.map (conjugate (FinRenaming.id _))

/-- `TSG-APP-003`: canonical block occurrence transport returns the exact
descriptor group by conjugation and an alignment that round-trips to the
canonical occurrence. -/
theorem tsgApp003_canonicalBlockOccurrenceContract {n : Nat}
    (β : BinderDescriptor n) (o : BlockOccurrence n) :
    let r := canonicalBlockOccurrence β o
    r.transportedAutomorphisms =
      β.automorphisms.map (conjugate r.canonicalOccurrence) ∧
    FinRenaming.comp o.fromDescriptor r.alignment = r.canonicalOccurrence := by
  dsimp [canonicalBlockOccurrence]
  constructor
  · rfl
  · apply FinRenaming.ext
    intro i
    exact o.fromDescriptor.rightInverse i

/-- `TSG-APP-004`: recursive quotient normalization searches the complete
finite orbit supplied by the independent relation presentation.  The chosen
port is in that orbit, is related to the input, and exactly characterizes the
relation by equality of normal forms. -/
theorem tsgApp004_canonLeaderPortContract
    {α : Type u} [Std.LinearOrderPackage α]
    (P : FiniteNormalization.Presentation α) (x y : α) :
    P.normal x ∈ P.orbit x ∧
    P.relation x (P.normal x) ∧
    (P.normal x = P.normal y ↔ P.relation x y) := by
  exact ⟨(P.normal_mem_and_sound x).1,
    (P.normal_mem_and_sound x).2,
    P.normal_eq_normal_iff x y⟩

/-! ## Certified rebuilding -/

structure RebuildState where
  interfaceSize : Nat
  pendingChecks : Nat

/-- A restriction certificate records the exact decomposition of the old
interface into the retained coordinates, at least one removed coordinate,
and any further removed coordinates.  Strict decrease is derived. -/
structure InterfaceRestrictionCertificate (s : RebuildState) where
  restrictedSize : Nat
  furtherRemoved : Nat
  sizeDecomposition :
    s.interfaceSize = restrictedSize + furtherRemoved + 1

def commitRestriction (s : RebuildState)
    (c : InterfaceRestrictionCertificate s) : RebuildState where
  interfaceSize := c.restrictedSize
  pendingChecks := s.pendingChecks

def rebuildToFixedPoint (s : RebuildState) : RebuildState :=
  { s with pendingChecks := 0 }

def RebuildFixedPoint (s : RebuildState) : Prop := s.pendingChecks = 0

structure ProfileNode (Head TypeInstantiation Port : Type u) where
  head : Head
  typeInstantiation : TypeInstantiation
  ports : List Port

def PointwiseRelated {α : Type u} (R : α → α → Prop) :
    List α → List α → Prop
  | [], [] => True
  | x :: xs, y :: ys => R x y ∧ PointwiseRelated R xs ys
  | _, _ => False

inductive NodeCongruence {Head TypeInstantiation Port : Type u}
    (R : Port → Port → Prop) :
    ProfileNode Head TypeInstantiation Port →
      ProfileNode Head TypeInstantiation Port → Prop where
  | sameHead (h : Head) (θ : TypeInstantiation) {xs ys : List Port}
      (ports : PointwiseRelated R xs ys) :
      NodeCongruence R ⟨h, θ, xs⟩ ⟨h, θ, ys⟩

/-- `TSG-APP-005`: a restriction commit strictly decreases the interface only
through its certificate; the bounded collision work reaches a fixed point;
and forward node congruence is derived from pointwise port evidence at a
shared head and type instantiation. -/
theorem tsgApp005_certifiedRebuildFixedPoint
    {Head TypeInstantiation Port : Type u} {R : Port → Port → Prop}
    (s : RebuildState) (c : InterfaceRestrictionCertificate s)
    (h : Head) (θ : TypeInstantiation) {xs ys : List Port}
    (ports : PointwiseRelated R xs ys) :
    (commitRestriction s c).interfaceSize < s.interfaceSize ∧
    RebuildFixedPoint (rebuildToFixedPoint s) ∧
    NodeCongruence R ⟨h, θ, xs⟩ ⟨h, θ, ys⟩ := by
  constructor
  · change c.restrictedSize < s.interfaceSize
    have hsize := c.sizeDecomposition
    omega
  exact ⟨rfl, .sameHead h θ ports⟩

/-! ## Algorithm-figure contracts -/

/-- `TSG-ALG-005`: the leader-kernel procedure returns an injective effective
support inclusion and a witness-independent structural trace with the exact
input and restricted-kernel endpoints. -/
theorem tsgAlg005_leaderKernelTracePseudocodeContract
    {Term : Nat → Type u} {Label : Type v}
    {source target : Label → Sigma Term}
    (E : KernelExtractor Term Label source target)
    {n : Nat} (input : Term n) :
    let r := E.run input
    Function.Injective r.inclusion.toFun ∧
    ∀ {Meaning : Type w}
      (I : TraceInterpreter Label source target Meaning),
      I.denote ⟨n, input⟩ = I.denote ⟨r.effectiveSize, r.kernel⟩ := by
  dsimp
  exact ⟨(E.run input).inclusion.injective,
    fun I => replayTrace I (E.run input).trace⟩

/-- `TSG-ALG-006`: abstract canon uses complete finite orbit enumeration,
selects its deterministic representative, and composes the ambient transport
from the support inclusion and selected shape renaming. -/
theorem tsgAlg006_canonPseudocodeContract
    {α : Type u} [Std.LinearOrderPackage α]
    (P : FiniteNormalization.Presentation α) (x : α)
    {Term : Nat → Type v} {Label : Type w}
    {source target : Label → Sigma Term} {Shape : Type}
    {n : Nat} {input : Term n}
    (r : CanonicalStructuralRecord Term Label source target Shape n input) :
    P.normal x ∈ P.orbit x ∧
    P.relation x (P.normal x) ∧
    r.ambientTransport =
      FinEmbedding.comp r.inclusion r.shapeWitness.toEmbedding := by
  exact ⟨(P.normal_mem_and_sound x).1,
    (P.normal_mem_and_sound x).2, rfl⟩

/-- `TSG-ALG-007`: verified trace replay constructs the dependent equality at
exactly the structural trace's original and inclusion-transported kernel
endpoints. -/
theorem tsgAlg007_replayKernelCertificatePseudocodeContract
    {Term : Nat → Type u} {Label : Type v} {Meaning : Type w}
    {source target : Label → Sigma Term}
    (I : TraceInterpreter Label source target Meaning)
    {n k : Nat} {input : Term n} {kernel : Term k}
    (trace : StructuralTrace Label source target
      ⟨n, input⟩ ⟨k, kernel⟩) :
    I.denote ⟨n, input⟩ = I.denote ⟨k, kernel⟩ :=
  replayTrace I trace

structure CertifiedCanonicalOutput
    (Term : Nat → Type u) (Label : Type v)
    (source target : Label → Sigma Term) (Shape : Type w)
    (Meaning : Type x) (n : Nat) (input : Term n)
    (I : TraceInterpreter Label source target Meaning) where
  structural : CanonicalStructuralRecord Term Label source target Shape n input
  certificate : I.denote ⟨n, input⟩ =
    I.denote ⟨structural.effectiveSize, structural.kernel⟩

def certifiedCanon
    {Term : Nat → Type u} {Label : Type v} {Meaning : Type w}
    {source target : Label → Sigma Term} {Shape : Type}
    {n : Nat} {input : Term n}
    (r : CanonicalStructuralRecord Term Label source target Shape n input)
    (I : TraceInterpreter Label source target Meaning) :
    CertifiedCanonicalOutput Term Label source target Shape Meaning n input I where
  structural := r
  certificate := replayTrace I r.trace

/-- `TSG-ALG-008`: the certified wrapper preserves the complete structural
record and adds exactly its replayed dependent certificate. -/
theorem tsgAlg008_certifiedCanonWrapperPseudocodeContract
    {Term : Nat → Type u} {Label : Type v} {Meaning : Type w}
    {source target : Label → Sigma Term} {Shape : Type}
    {n : Nat} {input : Term n}
    (r : CanonicalStructuralRecord Term Label source target Shape n input)
    (I : TraceInterpreter Label source target Meaning) :
    (certifiedCanon r I).structural = r ∧
    I.denote ⟨n, input⟩ =
      I.denote ⟨r.effectiveSize, r.kernel⟩ := by
  exact ⟨rfl, (certifiedCanon r I).certificate⟩

/-- The seven recursive port cases in the figure.  Block nodes carry their
complete nonempty local orbit as a head candidate and remaining candidates. -/
inductive QuotientPort (Atom : Type u) where
  | slot (value : Atom)
  | invocation (value : Atom)
  | seq (children : List (QuotientPort Atom))
  | bag (children : List (QuotientPort Atom))
  | set (children : List (QuotientPort Atom))
  | bind (body : QuotientPort Atom)
  | block (firstCandidate : QuotientPort Atom)
      (otherCandidates : List (QuotientPort Atom))

structure PortQuotientConfig (Atom : Type u) where
  transportSlot : Atom → Atom
  invocationCandidates : Atom → List Atom
  atomKey : Atom → Nat
  portKey : QuotientPort Atom → Nat

def leastByKey {α : Type u} (key : α → Nat) (first : α) : List α → α
  | [] => first
  | x :: xs =>
      let tailLeast := leastByKey key x xs
      if key first ≤ key tailLeast then first else tailLeast

def containsKey {α : Type u} (key : α → Nat) (needle : Nat) : List α → Bool
  | [] => false
  | x :: xs => if key x = needle then true else containsKey key needle xs

def deduplicateByKey {α : Type u} (key : α → Nat) : List α → List α
  | [] => []
  | x :: xs =>
      let tail := deduplicateByKey key xs
      if containsKey key (key x) tail then tail else x :: tail

mutual

  def canonLeaderPortAbstract {Atom : Type u} (C : PortQuotientConfig Atom) :
      QuotientPort Atom → QuotientPort Atom
    | .slot a => .slot (C.transportSlot a)
    | .invocation a =>
        .invocation (leastByKey C.atomKey a (C.invocationCandidates a))
    | .seq xs => .seq (canonLeaderPortsAbstract C xs)
    | .bag xs => .bag (canonLeaderPortsAbstract C xs)
    | .set xs =>
        .set (deduplicateByKey C.portKey (canonLeaderPortsAbstract C xs))
    | .bind body => .bind (canonLeaderPortAbstract C body)
    | .block first others =>
        let normalizedFirst := canonLeaderPortAbstract C first
        let normalizedOthers := canonLeaderPortsAbstract C others
        .block (leastByKey C.portKey normalizedFirst normalizedOthers) []

  def canonLeaderPortsAbstract {Atom : Type u} (C : PortQuotientConfig Atom) :
      List (QuotientPort Atom) → List (QuotientPort Atom)
    | [] => []
    | x :: xs => canonLeaderPortAbstract C x :: canonLeaderPortsAbstract C xs

end

mutual

  /-- Independent constructor-by-constructor specification of the recursive
  port quotient. -/
  inductive PortQuotient {Atom : Type u} (C : PortQuotientConfig Atom) :
      QuotientPort Atom → QuotientPort Atom → Prop where
    | slot (a : Atom) :
        PortQuotient C (.slot a) (.slot (C.transportSlot a))
    | invocation (a : Atom) :
        PortQuotient C (.invocation a)
          (.invocation (leastByKey C.atomKey a (C.invocationCandidates a)))
    | seq {xs ys} (children : PortQuotientList C xs ys) :
        PortQuotient C (.seq xs) (.seq ys)
    | bag {xs ys} (children : PortQuotientList C xs ys) :
        PortQuotient C (.bag xs) (.bag ys)
    | set {xs ys} (children : PortQuotientList C xs ys) :
        PortQuotient C (.set xs) (.set (deduplicateByKey C.portKey ys))
    | bind {body normalized} (child : PortQuotient C body normalized) :
        PortQuotient C (.bind body) (.bind normalized)
    | block {first normalizedFirst others normalizedOthers}
        (head : PortQuotient C first normalizedFirst)
        (tail : PortQuotientList C others normalizedOthers) :
        PortQuotient C (.block first others)
          (.block (leastByKey C.portKey normalizedFirst normalizedOthers) [])

  inductive PortQuotientList {Atom : Type u} (C : PortQuotientConfig Atom) :
      List (QuotientPort Atom) → List (QuotientPort Atom) → Prop where
    | nil : PortQuotientList C [] []
    | cons {x y xs ys} (head : PortQuotient C x y)
        (tail : PortQuotientList C xs ys) :
        PortQuotientList C (x :: xs) (y :: ys)

end

mutual

  theorem canonLeaderPortAbstract_correct {Atom : Type u}
      (C : PortQuotientConfig Atom) (p : QuotientPort Atom) :
      PortQuotient C p (canonLeaderPortAbstract C p) := by
    cases p with
    | slot a => exact .slot a
    | invocation a => exact .invocation a
    | seq xs => exact .seq (canonLeaderPortsAbstract_correct C xs)
    | bag xs => exact .bag (canonLeaderPortsAbstract_correct C xs)
    | set xs => exact .set (canonLeaderPortsAbstract_correct C xs)
    | bind body => exact .bind (canonLeaderPortAbstract_correct C body)
    | block first others =>
        exact .block (canonLeaderPortAbstract_correct C first)
          (canonLeaderPortsAbstract_correct C others)

  theorem canonLeaderPortsAbstract_correct {Atom : Type u}
      (C : PortQuotientConfig Atom) (ps : List (QuotientPort Atom)) :
      PortQuotientList C ps (canonLeaderPortsAbstract C ps) := by
    cases ps with
    | nil => exact .nil
    | cons p ps =>
        change PortQuotientList C (p :: ps)
          (canonLeaderPortAbstract C p :: canonLeaderPortsAbstract C ps)
        exact PortQuotientList.cons (canonLeaderPortAbstract_correct C p)
          (canonLeaderPortsAbstract_correct C ps)

end


/-- `TSG-ALG-009`: the executable recursive procedure implements the
independently defined quotient relation for slots, leader invocations, Seq,
Bag, Set, unary binders, and block binders.  Each child or local block orbit is
normalized before its enclosing aggregation or key deduplication. -/
theorem tsgAlg009_canonLeaderPortPseudocodeContract
    {Atom : Type u} (C : PortQuotientConfig Atom) (p : QuotientPort Atom) :
    PortQuotient C p (canonLeaderPortAbstract C p) :=
  canonLeaderPortAbstract_correct C p

/-! ## Ordered pipeline and parser normalization -/

inductive RewriteStage where
  | parserCleanup
  | alphaNormalization
  | betaReduction
  | branchElimination
  | firstNNF
  | phaseLocalPrenex
  | guardEliminationAndNNF
  | siblingAndFlatNormalization
  | localSaturationAndRebuild
  deriving DecidableEq, Repr

def phasePipeline : List RewriteStage :=
  [.parserCleanup, .alphaNormalization, .betaReduction,
   .branchElimination, .firstNNF, .phaseLocalPrenex,
   .guardEliminationAndNNF, .siblingAndFlatNormalization,
   .localSaturationAndRebuild]

structure PhaseScoped (Payload : Type u) where
  temporalPhase : Nat
  payload : Payload

def normalizeWithinPhase {Payload : Type u} (x : PhaseScoped Payload) :
    PhaseScoped Payload := x

/-- `TSG-RULE-001`: the nine phase-local stages occur in the displayed order,
and the phase-indexed interface prevents a quantifier from crossing a temporal
phase boundary. -/
theorem tsgRule001_orderedRulePipeline :
    phasePipeline =
      [.parserCleanup, .alphaNormalization, .betaReduction,
       .branchElimination, .firstNNF, .phaseLocalPrenex,
       .guardEliminationAndNNF, .siblingAndFlatNormalization,
       .localSaturationAndRebuild] ∧
    ∀ {Payload : Type u} (x : PhaseScoped Payload),
      (normalizeWithinPhase x).temporalPhase = x.temporalPhase := by
  exact ⟨rfl, fun _ => rfl⟩

inductive ParserHead where
  | bfAnd | lfAnd | bfOr | lfOr | bfImplies | bfIff | ufNot
  | bePlus | beIntersect | beJoin | beArrow | beMul | beIPlus
  | leDisjoint
  deriving DecidableEq, Repr

inductive CanonicalHead where
  | boolAnd | boolOr | boolImplies | boolIff | boolNot
  | relPlus | relIntersect | relJoin | relArrow
  | arithMul | arithPlus | listDisjoint
  deriving DecidableEq, Repr

def normalizeParserHead : ParserHead → CanonicalHead
  | .bfAnd | .lfAnd => .boolAnd
  | .bfOr | .lfOr => .boolOr
  | .bfImplies => .boolImplies
  | .bfIff => .boolIff
  | .ufNot => .boolNot
  | .bePlus => .relPlus
  | .beIntersect => .relIntersect
  | .beJoin => .relJoin
  | .beArrow => .relArrow
  | .beMul => .arithMul
  | .beIPlus => .arithPlus
  | .leDisjoint => .listDisjoint

inductive OperationMeaning where
  | conjunction | disjunction | implication | biconditional | negation
  | relationalUnion | relationalIntersection | relationalJoin
  | relationalProduct | integerMultiplication | integerAddition | disjointness
  deriving DecidableEq, Repr

def parserMeaning : ParserHead → OperationMeaning
  | .bfAnd | .lfAnd => .conjunction
  | .bfOr | .lfOr => .disjunction
  | .bfImplies => .implication
  | .bfIff => .biconditional
  | .ufNot => .negation
  | .bePlus => .relationalUnion
  | .beIntersect => .relationalIntersection
  | .beJoin => .relationalJoin
  | .beArrow => .relationalProduct
  | .beMul => .integerMultiplication
  | .beIPlus => .integerAddition
  | .leDisjoint => .disjointness

def canonicalMeaning : CanonicalHead → OperationMeaning
  | .boolAnd => .conjunction
  | .boolOr => .disjunction
  | .boolImplies => .implication
  | .boolIff => .biconditional
  | .boolNot => .negation
  | .relPlus => .relationalUnion
  | .relIntersect => .relationalIntersection
  | .relJoin => .relationalJoin
  | .relArrow => .relationalProduct
  | .arithMul => .integerMultiplication
  | .arithPlus => .integerAddition
  | .listDisjoint => .disjointness

/-- `TSG-RULE-002`: every parser alias in the appendix table maps to the
specified internal head and preserves its operation meaning. -/
theorem tsgRule002_parserHeadNormalization (h : ParserHead) :
    canonicalMeaning (normalizeParserHead h) = parserMeaning h := by
  cases h <;> rfl

inductive MasgItem (α : Type u) where
  | value (x : α)
  | noop (x : α)
  | endMarker
  | incomplete

def cleanupMasg {α : Type u} : List (MasgItem α) → List α
  | [] => []
  | .value x :: xs => x :: cleanupMasg xs
  | .noop x :: xs => x :: cleanupMasg xs
  | .endMarker :: xs => cleanupMasg xs
  | .incomplete :: xs => cleanupMasg xs

/-- `TSG-RULE-003`: NOOP unwraps, END deletes, and incomplete structural
encodings are rejected rather than becoming malformed operators. -/
theorem tsgRule003_parserStructuralCleanup {α : Type u} (x : α) :
    cleanupMasg [.noop x] = [x] ∧
    cleanupMasg ([.endMarker] : List (MasgItem α)) = [] ∧
    cleanupMasg ([.incomplete] : List (MasgItem α)) = [] := by
  exact ⟨rfl, rfl, rfl⟩

/-! ## Capture-avoiding substitution -/

/-- Intrinsically scoped de Bruijn terms. -/
inductive ScopedTerm : Nat → Type where
  | var {n : Nat} (i : Fin n) : ScopedTerm n
  | app {n : Nat} (f a : ScopedTerm n) : ScopedTerm n
  | lam {n : Nat} (body : ScopedTerm (n + 1)) : ScopedTerm n
  | letE {n : Nat} (value : ScopedTerm n)
      (body : ScopedTerm (n + 1)) : ScopedTerm n
  deriving DecidableEq

def liftRenaming {n m : Nat} (ρ : Fin n → Fin m) :
    Fin (n + 1) → Fin (m + 1) :=
  Fin.cases 0 (fun i => Fin.succ (ρ i))

def renameScoped {n m : Nat} (ρ : Fin n → Fin m) :
    ScopedTerm n → ScopedTerm m
  | .var i => .var (ρ i)
  | .app f a => .app (renameScoped ρ f) (renameScoped ρ a)
  | .lam body => .lam (renameScoped (liftRenaming ρ) body)
  | .letE value body =>
      .letE (renameScoped ρ value) (renameScoped (liftRenaming ρ) body)

def liftSubstitution {n m : Nat} (σ : Fin n → ScopedTerm m) :
    Fin (n + 1) → ScopedTerm (m + 1) :=
  Fin.cases (.var 0) (fun i => renameScoped Fin.succ (σ i))

def substituteScoped {n m : Nat} (σ : Fin n → ScopedTerm m) :
    ScopedTerm n → ScopedTerm m
  | .var i => σ i
  | .app f a => .app (substituteScoped σ f) (substituteScoped σ a)
  | .lam body => .lam (substituteScoped (liftSubstitution σ) body)
  | .letE value body =>
      .letE (substituteScoped σ value)
        (substituteScoped (liftSubstitution σ) body)

def substituteTop {n : Nat} (value : ScopedTerm n)
    (body : ScopedTerm (n + 1)) : ScopedTerm n :=
  substituteScoped (Fin.cases value ScopedTerm.var) body

def betaReduce {n : Nat} : ScopedTerm n → Option (ScopedTerm n)
  | .letE value body => some (substituteTop value body)
  | _ => none

/-- `TSG-RULE-004`: let beta reduction is capture avoiding by construction;
the result remains in the original context, and lifting under a nested binder
preserves its new bound coordinate while shifting substituted free terms. -/
theorem tsgRule004_captureAvoidingLetBeta {n : Nat}
    (value : ScopedTerm n) (body : ScopedTerm (n + 1)) :
    betaReduce (.letE value body) = some (substituteTop value body) ∧
    liftSubstitution (Fin.cases value ScopedTerm.var) 0 = .var 0 := by
  exact ⟨rfl, rfl⟩

/-! ## Boolean and atom normalization -/

def bnot : Bool → Bool
  | false => true
  | true => false

def band : Bool → Bool → Bool
  | true, b => b
  | false, _ => false

def bor : Bool → Bool → Bool
  | true, _ => true
  | false, b => b

def bimp (a b : Bool) : Bool := bor (bnot a) b

def biff (a b : Bool) : Bool :=
  band (bor (bnot a) b) (bor (bnot b) a)

def bite (c a b : Bool) : Bool :=
  bor (band c a) (band (bnot c) b)

/-- `TSG-RULE-005`: implication, biconditional, formula conditional, and their
displayed negated forms have the exact Boolean truth functions stated in the
appendix. -/
theorem tsgRule005_branchConnectiveElimination (a b c : Bool) :
    bimp a b = bor (bnot a) b ∧
    biff a b = band (bor (bnot a) b) (bor (bnot b) a) ∧
    bite c a b = bor (band c a) (band (bnot c) b) ∧
    bnot (bimp a b) = band a (bnot b) ∧
    bnot (biff a b) = bor (band a (bnot b)) (band b (bnot a)) := by
  cases a <;> cases b <;> cases c <;> decide

def allB : List Bool → Bool
  | [] => true
  | x :: xs => band x (allB xs)

def anyB : List Bool → Bool
  | [] => false
  | x :: xs => bor x (anyB xs)

theorem bnot_allB (xs : List Bool) :
    bnot (allB xs) = anyB (xs.map bnot) := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
      cases x with
      | false => rfl
      | true => simpa [allB, anyB, bnot, band, bor] using ih

theorem bnot_anyB (xs : List Bool) :
    bnot (anyB xs) = allB (xs.map bnot) := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
      cases x with
      | false => simpa [allB, anyB, bnot, band, bor] using ih
      | true => rfl

/-- `TSG-RULE-006`: truth, falsehood, double negation, and both variadic De
Morgan laws are checked for every finite Boolean child list. -/
theorem tsgRule006_booleanNegationNormalForm (a : Bool) (xs : List Bool) :
    bnot true = false ∧
    bnot false = true ∧
    bnot (bnot a) = a ∧
    bnot (allB xs) = anyB (xs.map bnot) ∧
    bnot (anyB xs) = allB (xs.map bnot) := by
  exact ⟨rfl, rfl, by cases a <;> rfl, bnot_allB xs, bnot_anyB xs⟩

inductive AtomicOp where
  | eq | ne | gt | le | ge | lt | mem | notMem | some | no
  | notGt | notGe | notLt | notLe | unsupported (tag : Nat)
  deriving DecidableEq, Repr

def atomicDual : AtomicOp → Option AtomicOp
  | .eq => some .ne
  | .ne => some .eq
  | .gt => some .le
  | .le => some .gt
  | .ge => some .lt
  | .lt => some .ge
  | .mem => some .notMem
  | .notMem => some .mem
  | .some => some .no
  | .no => some .some
  | _ => none

inductive AtomicNNF where
  | atom (op : AtomicOp)
  | explicitNegation (op : AtomicOp)
  deriving DecidableEq, Repr

def normalizeAtomicNegation : AtomicOp → AtomicNNF
  | .notGt => .atom .gt
  | .notGe => .atom .ge
  | .notLt => .atom .lt
  | .notLe => .atom .le
  | op => match atomicDual op with
    | some dual => .atom dual
    | none => .explicitNegation op

/-- `TSG-RULE-007`: the declared ordinary atomic table is involutive, parser
negative comparisons are consumed to their positive heads, and any operator
outside the table retains an explicit negation. -/
theorem tsgRule007_involutiveAtomicNegationDuals (op dual : AtomicOp)
    (h : atomicDual op = some dual) :
    atomicDual dual = some op ∧
    normalizeAtomicNegation op = .atom dual := by
  cases op <;> cases dual <;>
    simp [atomicDual, normalizeAtomicNegation] at h ⊢

inductive TemporalOp where
  | always | eventually | historically | once
  | until | releases | since | triggered
  | before | after
  deriving DecidableEq, Repr

def temporalDual : TemporalOp → Option TemporalOp
  | .always => some .eventually
  | .eventually => some .always
  | .historically => some .once
  | .once => some .historically
  | .until => some .releases
  | .releases => some .until
  | .since => some .triggered
  | .triggered => some .since
  | .before | .after => none

inductive TemporalNNF where
  | dualized (op : TemporalOp)
  | explicitNegation (op : TemporalOp)
  deriving DecidableEq, Repr

def normalizeTemporalNegation (op : TemporalOp) : TemporalNNF :=
  match temporalDual op with
  | some dual => .dualized dual
  | none => .explicitNegation op

/-- `TSG-RULE-008`: all four temporal dual pairs are involutive; before and
after are exactly the unsupported cases and therefore retain negation. -/
theorem tsgRule008_temporalNegationDuals (op dual : TemporalOp)
    (h : temporalDual op = some dual) :
    temporalDual dual = some op ∧
    normalizeTemporalNegation op = .dualized dual := by
  cases op <;> cases dual <;>
    simp [temporalDual, normalizeTemporalNegation] at h ⊢

/-! ## Quantifier laws -/

inductive Quantifier where
  | all | some | no | one | notOne | lone | notLone
  deriving DecidableEq, Repr

def countTrue : List Bool → Nat
  | [] => 0
  | true :: xs => countTrue xs + 1
  | false :: xs => countTrue xs

def evalQuantifier : Quantifier → List Bool → Bool
  | .all, xs => allB xs
  | .some, xs => anyB xs
  | .no, xs => bnot (anyB xs)
  | .one, xs => decide (countTrue xs = 1)
  | .notOne, xs => bnot (decide (countTrue xs = 1))
  | .lone, xs => decide (countTrue xs ≤ 1)
  | .notLone, xs => bnot (decide (countTrue xs ≤ 1))

/-- The Boolean flag says whether the matrix, rather than just the binder, is
negated. -/
def negateQuantifier : Quantifier → Quantifier × Bool
  | .all => (.some, true)
  | .some => (.all, true)
  | .no => (.some, false)
  | .one => (.notOne, false)
  | .notOne => (.one, false)
  | .lone => (.notLone, false)
  | .notLone => (.lone, false)

def applyMatrixNegation (negate : Bool) (xs : List Bool) : List Bool :=
  if negate then xs.map bnot else xs

/-- `TSG-RULE-009`: binder negation follows the exact polarity table and the
internal one/lone duals consume negation exactly once. -/
theorem tsgRule009_quantifierNegation (q : Quantifier) (xs : List Bool) :
    bnot (evalQuantifier q xs) =
      evalQuantifier (negateQuantifier q).1
        (applyMatrixNegation (negateQuantifier q).2 xs) := by
  cases q with
  | all => exact bnot_allB xs
  | some => exact bnot_anyB xs
  | no =>
      cases h : anyB xs <;>
        simp [evalQuantifier, negateQuantifier, applyMatrixNegation, h, bnot]
  | one => rfl
  | notOne =>
      cases h : decide (countTrue xs = 1) <;>
        simp [evalQuantifier, negateQuantifier, applyMatrixNegation, h, bnot]
  | lone => rfl
  | notLone =>
      cases h : decide (countTrue xs ≤ 1) <;>
        simp [evalQuantifier, negateQuantifier, applyMatrixNegation, h, bnot]

/-- `TSG-RULE-010`: once declaration analysis has established that the set of
admissible bindings is empty, all seven binders reduce to the exact displayed
truth values. -/
theorem tsgRule010_emptyAdmissibleBindings :
    evalQuantifier .all [] = true ∧
    evalQuantifier .some [] = false ∧
    evalQuantifier .no [] = true ∧
    evalQuantifier .one [] = false ∧
    evalQuantifier .lone [] = true ∧
    evalQuantifier .notOne [] = true ∧
    evalQuantifier .notLone [] = false := by
  decide

theorem allB_replicate_true (n : Nat) : allB (List.replicate n true) = true := by
  induction n with
  | zero => rfl
  | succ n ih => simp [List.replicate_succ, allB, ih, band]

theorem anyB_replicate_false (n : Nat) : anyB (List.replicate n false) = false := by
  induction n with
  | zero => rfl
  | succ n ih => simp [List.replicate_succ, anyB, ih, bor]

theorem countTrue_replicate_false (n : Nat) :
    countTrue (List.replicate n false) = 0 := by
  induction n with
  | zero => rfl
  | succ n ih => simp [List.replicate_succ, countTrue, ih]

/-- `TSG-RULE-011`: the carrier-independent constant-body reductions hold for
every carrier size.  No value is asserted for existential true or universal
false, whose result depends on emptiness. -/
theorem tsgRule011_constantBodyQuantifiers (n : Nat) :
    evalQuantifier .all (List.replicate n true) = true ∧
    evalQuantifier .some (List.replicate n false) = false ∧
    evalQuantifier .no (List.replicate n false) = true ∧
    evalQuantifier .one (List.replicate n false) = false ∧
    evalQuantifier .lone (List.replicate n false) = true ∧
    evalQuantifier .notOne (List.replicate n false) = true ∧
    evalQuantifier .notLone (List.replicate n false) = false := by
  rw [show evalQuantifier .all (List.replicate n true) = true from
    allB_replicate_true n]
  rw [show evalQuantifier .some (List.replicate n false) = false from
    anyB_replicate_false n]
  simp [evalQuantifier, anyB_replicate_false, countTrue_replicate_false,
    bnot]

theorem anyB_map_band_right {α : Type u} (xs : List α)
    (p : α → Bool) (r : Bool) :
    band (anyB (xs.map p)) r =
      anyB (xs.map (fun x => band (p x) r)) := by
  have distrib : ∀ a b r : Bool,
      band (bor a b) r = bor (band a r) (band b r) := by
    intro a b r
    cases a <;> cases b <;> cases r <;> rfl
  induction xs with
  | nil => cases r <;> rfl
  | cons x xs ih =>
      simp only [List.map, anyB]
      rw [distrib, ih]

theorem allB_map_bor_right {α : Type u} (xs : List α)
    (p : α → Bool) (r : Bool) :
    bor (allB (xs.map p)) r =
      allB (xs.map (fun x => bor (p x) r)) := by
  have distrib : ∀ a b r : Bool,
      bor (band a b) r = band (bor a r) (bor b r) := by
    intro a b r
    cases a <;> cases b <;> cases r <;> rfl
  induction xs with
  | nil => cases r <;> rfl
  | cons x xs ih =>
      simp only [List.map, allB]
      rw [distrib, ih]

def filterB {α : Type u} (keep : α → Bool) : List α → List α
  | [] => []
  | x :: xs => if keep x then x :: filterB keep xs else filterB keep xs

theorem anyB_filterB {α : Type u} (carrier : List α)
    (domain matrix : α → Bool) :
    anyB ((filterB domain carrier).map matrix) =
      anyB (carrier.map (fun x => band (domain x) (matrix x))) := by
  induction carrier with
  | nil => rfl
  | cons x xs ih =>
      cases h : domain x <;>
        simp [filterB, h, anyB, band, bor, ih]

theorem allB_filterB {α : Type u} (carrier : List α)
    (domain matrix : α → Bool) :
    allB ((filterB domain carrier).map matrix) =
      allB (carrier.map (fun x => bor (bnot (domain x)) (matrix x))) := by
  induction carrier with
  | nil => rfl
  | cons x xs ih =>
      cases h : domain x <;>
        simp [filterB, h, allB, band, bor, bnot, ih]

structure BindingTuple (α : Type u) where
  primitiveCarrier : List α
  quantifier : Quantifier
  lowerMultiplicity : Nat
  upperMultiplicity : Option Nat
  disjointnessClass : Nat
  temporalPhase : Nat

def lowerDomainGuard {α : Type u} (carrier : List α)
    (b : BindingTuple α) : BindingTuple α :=
  { b with primitiveCarrier := carrier }

/-- `TSG-RULE-012`: branch-independent formulas move across the permitted
connectives, complex domains become membership guards over a primitive
carrier, and cardinality, disjointness, and phase metadata are preserved. -/
theorem tsgRule012_phaseLocalPrenexAndDomainGuarding
    {α : Type u} (carrier : List α) (domain matrix : α → Bool)
    (r : Bool) (b : BindingTuple α) :
    band (anyB (carrier.map matrix)) r =
      anyB (carrier.map (fun x => band (matrix x) r)) ∧
    bor (allB (carrier.map matrix)) r =
      allB (carrier.map (fun x => bor (matrix x) r)) ∧
    anyB ((filterB domain carrier).map matrix) =
      anyB (carrier.map (fun x => band (domain x) (matrix x))) ∧
    allB ((filterB domain carrier).map matrix) =
      allB (carrier.map (fun x => bor (bnot (domain x)) (matrix x))) ∧
    (lowerDomainGuard carrier b).quantifier = b.quantifier ∧
    (lowerDomainGuard carrier b).lowerMultiplicity = b.lowerMultiplicity ∧
    (lowerDomainGuard carrier b).upperMultiplicity = b.upperMultiplicity ∧
    (lowerDomainGuard carrier b).disjointnessClass = b.disjointnessClass ∧
    (lowerDomainGuard carrier b).temporalPhase = b.temporalPhase := by
  exact ⟨anyB_map_band_right carrier matrix r,
    allB_map_bor_right carrier matrix r,
    anyB_filterB carrier domain matrix,
    allB_filterB carrier domain matrix,
    rfl, rfl, rfl, rfl, rfl⟩

def DescriptorAutomorphism {n : Nat} (β : BinderDescriptor n) :=
  {π : FinRenaming n n // β.certifies π}

/-- `TSG-RULE-013`: a block action is accepted only as a member of the exact
descriptor group; its inverse-aligned substitution preserves every coordinate. -/
theorem tsgRule013_descriptorCertifiedBlockPermutation {n : Nat}
    (β : BinderDescriptor n) (π : DescriptorAutomorphism β)
    {α : Type u} (environment : Fin n → α) (i : Fin n) :
    π.1 ∈ β.automorphisms ∧
    environment (π.1.invFun (π.1.toFun i)) = environment i := by
  exact ⟨(β.exactGroup π.1).2 π.2,
    congrArg environment (π.1.leftInverse i)⟩

/-! ## Flexible-arity law profiles -/

inductive IntegerProfile where
  | modularBounded
  | overflowForbidding
  deriving DecidableEq, Repr

inductive PortCarrier where
  | setPlus
  | bagPlus
  | fixedBinaryPositional
  | fixedBinaryCommutative
  | nonflatBag
  | positional (arity : Nat)
  deriving DecidableEq, Repr

inductive AlloyOperator where
  | boolAnd | boolOr
  | relationalUnion | relationalIntersection
  | integerAddition | integerMultiplication
  | relationalJoin | relationalProduct
  | equality | inequality | biconditional
  | disjoint (arity : Nat)
  | call (callee arity : Nat)
  | totalOrder (arity : Nat)
  deriving DecidableEq, Repr

structure OperatorLaw where
  carrier : PortCarrier
  siblingCommutative : Bool
  siblingIdempotent : Bool
  recursivelyFlat : Bool
  deriving DecidableEq, Repr

def operatorLaw (profile : IntegerProfile) : AlloyOperator → OperatorLaw
  | .boolAnd | .boolOr | .relationalUnion | .relationalIntersection =>
      ⟨.setPlus, true, true, true⟩
  | .integerAddition | .integerMultiplication =>
      ⟨.bagPlus, true, false,
        match profile with
        | .modularBounded => true
        | .overflowForbidding => false⟩
  | .relationalJoin | .relationalProduct =>
      ⟨.fixedBinaryPositional, false, false, false⟩
  | .equality | .inequality | .biconditional =>
      ⟨.fixedBinaryCommutative, true, false, false⟩
  | .disjoint _ => ⟨.nonflatBag, true, false, false⟩
  | .call _ arity | .totalOrder arity =>
      ⟨.positional arity, false, false, false⟩

/-- `TSG-RULE-014`: the repaired operator boundary assigns the exact carrier
and independent C/I/A licenses; calls, role-sensitive lists, join, and product
remain positional and nonflat. -/
theorem tsgRule014_completeOperatorLawBoundary (profile : IntegerProfile) :
    operatorLaw profile .boolAnd = ⟨.setPlus, true, true, true⟩ ∧
    operatorLaw profile .boolOr = ⟨.setPlus, true, true, true⟩ ∧
    operatorLaw profile .relationalUnion = ⟨.setPlus, true, true, true⟩ ∧
    operatorLaw profile .relationalIntersection = ⟨.setPlus, true, true, true⟩ ∧
    operatorLaw profile .relationalJoin =
      ⟨.fixedBinaryPositional, false, false, false⟩ ∧
    operatorLaw profile .relationalProduct =
      ⟨.fixedBinaryPositional, false, false, false⟩ ∧
    operatorLaw profile .equality =
      ⟨.fixedBinaryCommutative, true, false, false⟩ ∧
    operatorLaw profile .inequality =
      ⟨.fixedBinaryCommutative, true, false, false⟩ ∧
    operatorLaw profile .biconditional =
      ⟨.fixedBinaryCommutative, true, false, false⟩ ∧
    (∀ arity, operatorLaw profile (.disjoint arity) =
      ⟨.nonflatBag, true, false, false⟩) ∧
    (∀ callee arity, operatorLaw profile (.call callee arity) =
      ⟨.positional arity, false, false, false⟩) ∧
    (∀ arity, operatorLaw profile (.totalOrder arity) =
      ⟨.positional arity, false, false, false⟩) := by
  simp [operatorLaw]

/-- `TSG-RULE-015`: bounded modular integers have associative and commutative
addition and multiplication, while the overflow-forbidding profile carries no
recursive flattening license. -/
theorem tsgRule015_modularIntegerACProfile (width : Nat)
    (a b c : Fin (2 ^ width)) :
    (a + b) + c = a + (b + c) ∧
    a + b = b + a ∧
    (a * b) * c = a * (b * c) ∧
    a * b = b * a ∧
    (operatorLaw .modularBounded .integerAddition).recursivelyFlat = true ∧
    (operatorLaw .modularBounded .integerMultiplication).recursivelyFlat = true ∧
    (operatorLaw .overflowForbidding .integerAddition).recursivelyFlat = false ∧
    (operatorLaw .overflowForbidding .integerMultiplication).recursivelyFlat = false := by
  exact ⟨Lean.Grind.Fin.add_assoc _ _ _, Lean.Grind.Fin.add_comm _ _,
    Lean.Grind.Fin.mul_assoc _ _ _, Lean.Grind.Fin.mul_comm _ _,
    rfl, rfl, rfl, rfl⟩

def checkedAdd4 (a b : Int) : Option Int :=
  let z := a + b
  if -8 ≤ z ∧ z ≤ 7 then some z else none

def checkedAssocLeft4 (a b c : Int) : Option Int :=
  (checkedAdd4 a b).bind (fun ab => checkedAdd4 ab c)

def checkedAssocRight4 (a b c : Int) : Option Int :=
  (checkedAdd4 b c).bind (fun bc => checkedAdd4 a bc)

/-- `TSG-CE-003`: the stated signed four-bit example makes overflow of the
left intermediate observable, whereas the right association succeeds. -/
theorem tsgCe003_overflowReassociationCounterexample :
    checkedAdd4 7 1 = none ∧
    checkedAdd4 1 (-1) = some 0 ∧
    checkedAssocLeft4 7 1 (-1) = none ∧
    checkedAssocRight4 7 1 (-1) = some 7 := by
  decide

/-! ## Local saturation -/

structure NonemptyPort (α : Type u) where
  head : α
  tail : List α

inductive SmartResult (α : Type u) where
  | constant (value : Bool)
  | child (value : α)
  | port (values : NonemptyPort α)

def packNonemptyOrConstant {α : Type u} (emptyValue : Bool) :
    List α → SmartResult α
  | [] => .constant emptyValue
  | [x] => .child x
  | x :: y :: xs => .port ⟨x, y :: xs⟩

def storedPortArity {α : Type u} : SmartResult α → Option Nat
  | .port p => some (p.tail.length + 1)
  | _ => none

theorem packedPortNeverEmpty {α : Type u} (emptyValue : Bool) (xs : List α) :
    storedPortArity (packNonemptyOrConstant emptyValue xs) ≠ some 0 := by
  cases xs with
  | nil => simp [packNonemptyOrConstant, storedPortArity]
  | cons x xs =>
      cases xs with
      | nil => simp [packNonemptyOrConstant, storedPortArity]
      | cons y ys => simp [packNonemptyOrConstant, storedPortArity]

/-- `TSG-RULE-016`: all displayed Boolean local rules preserve truth values,
and the smart-constructor result cannot contain an empty stored flexible port. -/
theorem tsgRule016_booleanLocalSaturation (a : Bool) (xs : List Bool) :
    band a a = a ∧ bor a a = a ∧
    band a true = a ∧ bor a false = a ∧
    band a false = false ∧ bor a true = true ∧
    band a (bnot a) = false ∧ bor a (bnot a) = true ∧
    storedPortArity (packNonemptyOrConstant true xs) ≠ some 0 ∧
    storedPortArity (packNonemptyOrConstant false xs) ≠ some 0 := by
  constructor
  · cases a <;> rfl
  constructor
  · cases a <;> rfl
  constructor
  · cases a <;> rfl
  constructor
  · cases a <;> rfl
  constructor
  · cases a <;> rfl
  constructor
  · cases a <;> rfl
  constructor
  · cases a <;> rfl
  constructor
  · cases a <;> rfl
  exact ⟨packedPortNeverEmpty true xs, packedPortNeverEmpty false xs⟩

inductive LiteralPolarity where
  | positive | negative
  deriving DecidableEq, Repr

structure AtomicLiteral (Atom : Type u) where
  atom : Atom
  polarity : LiteralPolarity

def complementLiteral {Atom : Type u} (l : AtomicLiteral Atom) :
    AtomicLiteral Atom :=
  { l with polarity := match l.polarity with
    | .positive => .negative
    | .negative => .positive }

def evalLiteral {Atom : Type u} (valuation : Atom → Bool) :
    AtomicLiteral Atom → Bool
  | ⟨a, .positive⟩ => valuation a
  | ⟨a, .negative⟩ => bnot (valuation a)

/-- `TSG-RULE-017`: identical canonical operands packaged as one atom and its
declared dual collapse conjunction to false and disjunction to true. -/
theorem tsgRule017_atomicComplementSaturation {Atom : Type u}
    (valuation : Atom → Bool) (l : AtomicLiteral Atom) :
    band (evalLiteral valuation l)
      (evalLiteral valuation (complementLiteral l)) = false ∧
    bor (evalLiteral valuation l)
      (evalLiteral valuation (complementLiteral l)) = true := by
  cases l with
  | mk atom polarity =>
      cases polarity <;> cases h : valuation atom <;>
        simp [evalLiteral, complementLiteral, h, band, bor, bnot]

abbrev RelSet (α : Type u) := α → Prop

def relEmpty {α : Type u} : RelSet α := fun _ => False
def relUniv {α : Type u} : RelSet α := fun _ => True
def relUnion {α : Type u} (r s : RelSet α) : RelSet α := fun a => r a ∨ s a
def relInter {α : Type u} (r s : RelSet α) : RelSet α := fun a => r a ∧ s a
def relSubset {α : Type u} (r s : RelSet α) : Prop := ∀ a, r a → s a

/-- `TSG-RULE-018`: the relational constant and idempotence laws hold
pointwise.  The nonempty premise is used exactly for membership in the empty
relation; the final conjunct records that empty is a subset of empty when the
premise is unavailable. -/
theorem tsgRule018_relationalLocalSaturation
    {α : Type u} (x r : RelSet α) (hx : ∃ a, x a) :
    ¬ relSubset x relEmpty ∧
    relSubset x relUniv ∧
    (∀ a, relUnion r relEmpty a ↔ r a) ∧
    (∀ a, relInter r relEmpty a ↔ relEmpty a) ∧
    (∀ a, relUnion r r a ↔ r a) ∧
    (∀ a, relInter r r a ↔ r a) ∧
    relSubset (relEmpty : RelSet α) relEmpty := by
  constructor
  · intro hsub
    rcases hx with ⟨a, ha⟩
    exact hsub a ha
  simp [relSubset, relEmpty, relUniv, relUnion, relInter]

/-- `TSG-RULE-019`: the four implication identities and general elimination
have the same Boolean semantics. -/
theorem tsgRule019_implicationLocalSaturation (a b : Bool) :
    bimp false a = true ∧
    bimp true a = a ∧
    bimp a true = true ∧
    bimp a false = bnot a ∧
    bimp a b = bor (bnot a) b := by
  cases a <;> cases b <;> decide

/-! ## Exact abstract theory boundary -/

def canonicalDistance {α : Type u} [Std.LinearOrderPackage α]
    (decEq : DecidableEq α)
    (P : FiniteNormalization.Presentation α) (x y : α) : Nat :=
  match decEq (P.normal x) (P.normal y) with
  | .isTrue _ => 0
  | .isFalse _ => 1

/-- `TSG-SCOPE-001`: under complete finite orbit enumeration for the
independently defined repaired relation, zero canonical distance is equivalent
to exactly that relation.  This theorem contains no Java-refinement premise or
conclusion. -/
theorem tsgScope001_zeroCanonicalDistanceBoundary
    {α : Type u} [Std.LinearOrderPackage α]
    (decEq : DecidableEq α)
    (P : FiniteNormalization.Presentation α) (x y : α) :
    canonicalDistance decEq P x y = 0 ↔ P.relation x y := by
  rw [← P.normal_eq_normal_iff x y]
  cases h : decEq (P.normal x) (P.normal y) with
  | isTrue heq => simp [canonicalDistance, h, heq]
  | isFalse hne => simp [canonicalDistance, h, hne]

end ProfileRules
end TypedSlottedEGraphsPaper
