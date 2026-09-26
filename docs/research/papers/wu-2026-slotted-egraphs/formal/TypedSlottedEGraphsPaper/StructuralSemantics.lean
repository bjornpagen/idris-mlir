import TypedSlottedEGraphsPaper.Certificates
import TypedSlottedEGraphsPaper.SyntaxSupport

namespace TypedSlottedEGraphsPaper

universe u v w x y z r

/-- Context-indexed atoms and their action by typed outer-context embeddings.
    The `bound` index is a typed de Bruijn scope; an outer embedding leaves it
    unchanged. -/
structure StructuralAtomAction (Ty : Type u) where
  Atom : TypedSlotContext.{u, v} Ty -> List Ty -> Ty -> Type w
  act : {source target : TypedSlotContext.{u, v} Ty} ->
    TypedSlotEmbedding source target -> {bound : List Ty} -> {output : Ty} ->
    Atom source bound output -> Atom target bound output

/-- The concrete atom syntax from `SyntaxSupport` is an instance of the
    structural atom interface; its embedding action is used without an
    additional compatibility premise. -/
def concreteScopedAtomStructuralAction
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op) :
    StructuralAtomAction.{u, v, max u v w} Ty where
  Atom := fun context bound output =>
    ScopedPortAtom signature context bound output
  act := by
    intro source target embedding bound output value
    exact ScopedPortAtom.act embedding value

/- A homogeneous, intrinsically typed structural calculus.  The constructors
    distinguish leaves, containers, unary binders, descriptor-governed binder
    blocks, and enclosing nodes.  Binder scopes are represented in the index,
    not by a global side condition. -/
mutual
  inductive StructuralSyntax {Ty : Type u}
      (A : StructuralAtomAction.{u, v, w} Ty)
      (Block : Type x) (blockTypes : Block -> List Ty)
      (Operator : Ty -> Type y) :
      TypedSlotContext.{u, v} Ty -> List Ty -> Ty -> Type _ where
    | atom {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
        {output : Ty} (value : A.Atom context bound output) :
        StructuralSyntax A Block blockTypes Operator context bound output
    | container {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
        {output : Ty} (kind : ContainerKind)
        (children : StructuralForest A Block blockTypes Operator context bound output) :
        StructuralSyntax A Block blockTypes Operator context bound output
    | binder {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
        {output : Ty} (boundType : Ty)
        (body : StructuralSyntax A Block blockTypes Operator context
          (boundType :: bound) output) :
        StructuralSyntax A Block blockTypes Operator context bound output
    | binderBlock {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
        {output : Ty} (descriptor : Block)
        (body : StructuralSyntax A Block blockTypes Operator context
          (blockTypes descriptor ++ bound) output) :
        StructuralSyntax A Block blockTypes Operator context bound output
    | node {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
        {output : Ty} (operator : Operator output)
        (children : StructuralForest A Block blockTypes Operator context bound output) :
        StructuralSyntax A Block blockTypes Operator context bound output

  /-- A proof-relevant sequence of structural children. -/
  inductive StructuralForest {Ty : Type u}
      (A : StructuralAtomAction.{u, v, w} Ty)
      (Block : Type x) (blockTypes : Block -> List Ty)
      (Operator : Ty -> Type y) :
      TypedSlotContext.{u, v} Ty -> List Ty -> Ty -> Type _ where
    | nil {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
        {output : Ty} :
        StructuralForest A Block blockTypes Operator context bound output
    | cons {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
        {output : Ty}
        (head : StructuralSyntax A Block blockTypes Operator context bound output)
        (tail : StructuralForest A Block blockTypes Operator context bound output) :
        StructuralForest A Block blockTypes Operator context bound output
end

namespace StructuralSyntax

mutual
  /-- Outer-context transport, defined by recursion over every structural
      constructor. -/
  def act {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
      {Block : Type x} {blockTypes : Block -> List Ty}
      {Operator : Ty -> Type y}
      {source target : TypedSlotContext.{u, v} Ty}
      (embedding : TypedSlotEmbedding source target)
      {bound : List Ty} {output : Ty} :
      StructuralSyntax A Block blockTypes Operator source bound output ->
        StructuralSyntax A Block blockTypes Operator target bound output
    | .atom value => .atom (A.act embedding value)
    | .container kind children =>
        .container kind (StructuralForest.act embedding children)
    | .binder boundType body => .binder boundType (act embedding body)
    | .binderBlock descriptor body =>
        .binderBlock descriptor (act embedding body)
    | .node operator children =>
        .node operator (StructuralForest.act embedding children)

  /-- Componentwise outer-context transport of a child sequence. -/
  def StructuralForest.act {Ty : Type u}
      {A : StructuralAtomAction.{u, v, w} Ty}
      {Block : Type x} {blockTypes : Block -> List Ty}
      {Operator : Ty -> Type y}
      {source target : TypedSlotContext.{u, v} Ty}
      (embedding : TypedSlotEmbedding source target)
      {bound : List Ty} {output : Ty} :
      StructuralForest A Block blockTypes Operator source bound output ->
        StructuralForest A Block blockTypes Operator target bound output
    | .nil => .nil
    | .cons head tail => .cons (act embedding head) (StructuralForest.act embedding tail)
end

end StructuralSyntax

/-- Local source-language constructors and their one-constructor naturality
    laws.  None of these fields states naturality of a complete structural
    value; that theorem is obtained below by structural recursion. -/
structure StructuralRealizer {Ty : Type u}
    (A : StructuralAtomAction.{u, v, w} Ty)
    (Block : Type x) (blockTypes : Block -> List Ty)
    (Operator : Ty -> Type y)
    (L : TypedTermLanguage.{u, v, z} Ty) where
  atom : {context : TypedSlotContext.{u, v} Ty} -> {bound : List Ty} ->
    {output : Ty} -> A.Atom context bound output -> L.Term context output
  container : {context : TypedSlotContext.{u, v} Ty} -> {bound : List Ty} ->
    {output : Ty} -> ContainerKind -> List (L.Term context output) ->
      L.Term context output
  binder : {context : TypedSlotContext.{u, v} Ty} -> {bound : List Ty} ->
    {output : Ty} -> (boundType : Ty) -> L.Term context output ->
      L.Term context output
  binderBlock : {context : TypedSlotContext.{u, v} Ty} ->
    {bound : List Ty} -> {output : Ty} ->
    (descriptor : Block) -> L.Term context output -> L.Term context output
  node : {context : TypedSlotContext.{u, v} Ty} -> {bound : List Ty} ->
    {output : Ty} -> Operator output -> List (L.Term context output) ->
      L.Term context output
  atomNatural : forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {bound : List Ty}
    {output : Ty} (value : A.Atom source bound output),
    atom (A.act embedding value) = L.rename embedding (atom value)
  containerNatural : forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {bound : List Ty}
    {output : Ty} (kind : ContainerKind) (children : List (L.Term source output)),
    container (context := target) (bound := bound) kind
        (children.map (fun child => L.rename embedding child)) =
      L.rename embedding (container (bound := bound) kind children)
  binderNatural : forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {bound : List Ty}
    {output : Ty} (boundType : Ty) (body : L.Term source output),
    binder (context := target) (bound := bound) boundType (L.rename embedding body) =
      L.rename embedding (binder (bound := bound) boundType body)
  binderBlockNatural : forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {bound : List Ty}
    {output : Ty} (descriptor : Block) (body : L.Term source output),
    binderBlock (context := target) (bound := bound) descriptor
        (L.rename embedding body) =
      L.rename embedding (binderBlock (bound := bound) descriptor body)
  nodeNatural : forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {bound : List Ty}
    {output : Ty} (operator : Operator output)
    (children : List (L.Term source output)),
    node (context := target) (bound := bound) operator
        (children.map (fun child => L.rename embedding child)) =
      L.rename embedding (node (bound := bound) operator children)

namespace StructuralRealizer

mutual
  /-- Structural realization into source terms. -/
  def realize {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
      {Block : Type x} {blockTypes : Block -> List Ty}
      {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
      (R : StructuralRealizer A Block blockTypes Operator L)
      {context : TypedSlotContext.{u, v} Ty} {bound : List Ty} {output : Ty} :
      StructuralSyntax A Block blockTypes Operator context bound output ->
        L.Term context output
    | .atom value => R.atom value
    | .container kind children =>
        R.container (bound := bound) kind (realizeForest R children)
    | .binder boundType body =>
        R.binder (bound := bound) boundType (realize R body)
    | .binderBlock descriptor body =>
        R.binderBlock (bound := bound) descriptor (realize R body)
    | .node operator children =>
        R.node (bound := bound) operator (realizeForest R children)

  /-- Realization of a child sequence. -/
  def realizeForest {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
      {Block : Type x} {blockTypes : Block -> List Ty}
      {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
      (R : StructuralRealizer A Block blockTypes Operator L)
      {context : TypedSlotContext.{u, v} Ty} {bound : List Ty} {output : Ty} :
      StructuralForest A Block blockTypes Operator context bound output ->
        List (L.Term context output)
    | .nil => []
    | .cons head tail => realize R head :: realizeForest R tail
end

/-- F21-strength theorem: realization commutes with every outer embedding.
    The mutual recursor supplies the structural induction hypotheses for both
    complete values and child sequences. -/
theorem structuralRealizationNaturality
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    (R : StructuralRealizer A Block blockTypes Operator L)
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {bound : List Ty} {output : Ty}
    (item : StructuralSyntax A Block blockTypes Operator source bound output) :
    realize R (StructuralSyntax.act embedding item) =
      L.rename embedding (realize R item) := by
  refine StructuralSyntax.rec
    (motive_1 := fun _ _ term =>
      realize R (StructuralSyntax.act embedding term) =
        L.rename embedding (realize R term))
    (motive_2 := fun _ _ terms =>
      realizeForest R (StructuralSyntax.StructuralForest.act embedding terms) =
        (realizeForest R terms).map (fun term => L.rename embedding term))
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ item
  · intro bound output value
    exact R.atomNatural embedding value
  · intro bound output kind children childrenIH
    rw [StructuralSyntax.act, realize]
    rw [childrenIH]
    exact R.containerNatural embedding kind (realizeForest R children)
  · intro bound output boundType body bodyIH
    rw [StructuralSyntax.act, realize]
    rw [bodyIH]
    exact R.binderNatural embedding boundType (realize R body)
  · intro bound output descriptor body bodyIH
    rw [StructuralSyntax.act, realize]
    rw [bodyIH]
    exact R.binderBlockNatural embedding descriptor (realize R body)
  · intro bound output operator children childrenIH
    rw [StructuralSyntax.act, realize]
    rw [childrenIH]
    exact R.nodeNatural embedding operator (realizeForest R children)
  · intro bound output
    rfl
  · intro bound output head tail headIH tailIH
    rw [StructuralSyntax.StructuralForest.act, realizeForest, realizeForest,
      List.map_cons, headIH, tailIH]

end StructuralRealizer

/-- Pointwise certificates for two source-term child sequences. -/
inductive StructuralCertificateForest {Ty : Type u}
    (L : TypedTermLanguage.{u, v, w} Ty)
    {context : TypedSlotContext.{u, v} Ty} {output : Ty} :
    List (L.Term context output) -> List (L.Term context output) -> Prop where
  | nil : StructuralCertificateForest L [] []
  | cons (head : TypedEquationalCertificate L left right)
      (tail : StructuralCertificateForest L lefts rights) :
      StructuralCertificateForest L (left :: lefts) (right :: rights)

/-- Only local proof obligations for the structural derivation.  Atom steps
    carry checked leaf laws.  Binder-block automorphisms carry descriptor-local
    witnesses.  Every other field is a forward congruence rule for one source
    constructor. -/
structure StructuralLocalLaws {Ty : Type u}
    (A : StructuralAtomAction.{u, v, w} Ty)
    (Block : Type x) (blockTypes : Block -> List Ty)
    (Operator : Ty -> Type y)
    (L : TypedTermLanguage.{u, v, z} Ty)
    (R : StructuralRealizer A Block blockTypes Operator L) where
  AtomStep : {source target : TypedSlotContext.{u, v} Ty} ->
    TypedSlotEmbedding source target -> {bound : List Ty} -> {output : Ty} ->
    A.Atom source bound output -> A.Atom target bound output -> Type r
  BlockAutomorphism : Block -> Type r
  atomCertificate : forall {source target : TypedSlotContext.{u, v} Ty}
    {embedding : TypedSlotEmbedding source target} {bound : List Ty}
    {output : Ty} {left : A.Atom source bound output}
    {right : A.Atom target bound output},
    AtomStep embedding left right ->
      TypedEquationalCertificate L
        (L.rename embedding (R.atom left)) (R.atom right)
  containerCongruence : forall {context : TypedSlotContext.{u, v} Ty}
    {bound : List Ty} {output : Ty} (kind : ContainerKind)
    {left right : List (L.Term context output)},
    StructuralCertificateForest L left right ->
      TypedEquationalCertificate L
        (R.container (bound := bound) kind left)
        (R.container (bound := bound) kind right)
  binderCongruence : forall {context : TypedSlotContext.{u, v} Ty}
    {bound : List Ty} {output : Ty} (boundType : Ty)
    {left right : L.Term context output},
    TypedEquationalCertificate L left right ->
      TypedEquationalCertificate L
        (R.binder (bound := bound) boundType left)
        (R.binder (bound := bound) boundType right)
  binderBlockCongruence : forall {context : TypedSlotContext.{u, v} Ty}
    {bound : List Ty} {output : Ty} (descriptor : Block)
    {left right : L.Term context output},
    TypedEquationalCertificate L left right ->
      TypedEquationalCertificate L
        (R.binderBlock (bound := bound) descriptor left)
        (R.binderBlock (bound := bound) descriptor right)
  binderBlockAutomorphismCongruence :
    forall {context : TypedSlotContext.{u, v} Ty}
    {bound : List Ty} {output : Ty} (descriptor : Block),
    BlockAutomorphism descriptor -> {left right : L.Term context output} ->
    TypedEquationalCertificate L left right ->
      TypedEquationalCertificate L
        (R.binderBlock (bound := bound) descriptor left)
        (R.binderBlock (bound := bound) descriptor right)
  nodeCongruence : forall {context : TypedSlotContext.{u, v} Ty}
    {bound : List Ty} {output : Ty} (operator : Operator output)
    {left right : List (L.Term context output)},
    StructuralCertificateForest L left right ->
      TypedEquationalCertificate L
        (R.node (bound := bound) operator left)
        (R.node (bound := bound) operator right)

/- The independent proof-relevant derivation used for both structural alpha
    reasoning and graph-relative port congruence.  In particular, it has no
    constructor accepting a certificate for two complete endpoint trees. -/
mutual
  inductive StructuralDerivation {Ty : Type u}
      {A : StructuralAtomAction.{u, v, w} Ty}
      {Block : Type x} {blockTypes : Block -> List Ty}
      {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
      {R : StructuralRealizer A Block blockTypes Operator L}
      (Q : StructuralLocalLaws A Block blockTypes Operator L R) :
      {source target : TypedSlotContext.{u, v} Ty} ->
      TypedSlotEmbedding source target ->
      {bound : List Ty} -> {output : Ty} ->
      StructuralSyntax A Block blockTypes Operator source bound output ->
      StructuralSyntax A Block blockTypes Operator target bound output -> Type _ where
    | atom {source target : TypedSlotContext.{u, v} Ty}
        {embedding : TypedSlotEmbedding source target}
        {bound : List Ty} {output : Ty}
        {left : A.Atom source bound output}
        {right : A.Atom target bound output}
        (step : Q.AtomStep embedding left right) :
        StructuralDerivation Q embedding (.atom left) (.atom right)
    | container {source target : TypedSlotContext.{u, v} Ty}
        {embedding : TypedSlotEmbedding source target}
        {bound : List Ty} {output : Ty} (kind : ContainerKind)
        {left : StructuralForest A Block blockTypes Operator source bound output}
        {right : StructuralForest A Block blockTypes Operator target bound output}
        (children : StructuralForestDerivation Q embedding left right) :
        StructuralDerivation Q embedding (.container kind left) (.container kind right)
    | binder {source target : TypedSlotContext.{u, v} Ty}
        {embedding : TypedSlotEmbedding source target}
        {bound : List Ty} {output : Ty} (boundType : Ty)
        {left : StructuralSyntax A Block blockTypes Operator source
          (boundType :: bound) output}
        {right : StructuralSyntax A Block blockTypes Operator target
          (boundType :: bound) output}
        (body : StructuralDerivation Q embedding left right) :
        StructuralDerivation Q embedding (.binder boundType left) (.binder boundType right)
    | binderBlock {source target : TypedSlotContext.{u, v} Ty}
        {embedding : TypedSlotEmbedding source target}
        {bound : List Ty} {output : Ty} (descriptor : Block)
        {left : StructuralSyntax A Block blockTypes Operator source
          (blockTypes descriptor ++ bound) output}
        {right : StructuralSyntax A Block blockTypes Operator target
          (blockTypes descriptor ++ bound) output}
        (body : StructuralDerivation Q embedding left right) :
        StructuralDerivation Q embedding
          (.binderBlock descriptor left) (.binderBlock descriptor right)
    | binderBlockAutomorphism {source target : TypedSlotContext.{u, v} Ty}
        {embedding : TypedSlotEmbedding source target}
        {bound : List Ty} {output : Ty} (descriptor : Block)
        (localLaw : Q.BlockAutomorphism descriptor)
        {left : StructuralSyntax A Block blockTypes Operator source
          (blockTypes descriptor ++ bound) output}
        {right : StructuralSyntax A Block blockTypes Operator target
          (blockTypes descriptor ++ bound) output}
        (body : StructuralDerivation Q embedding left right) :
        StructuralDerivation Q embedding
          (.binderBlock descriptor left) (.binderBlock descriptor right)
    | node {source target : TypedSlotContext.{u, v} Ty}
        {embedding : TypedSlotEmbedding source target}
        {bound : List Ty} {output : Ty} (operator : Operator output)
        {left : StructuralForest A Block blockTypes Operator source bound output}
        {right : StructuralForest A Block blockTypes Operator target bound output}
        (children : StructuralForestDerivation Q embedding left right) :
        StructuralDerivation Q embedding (.node operator left) (.node operator right)

  /-- Pointwise derivations for container and node children. -/
  inductive StructuralForestDerivation {Ty : Type u}
      {A : StructuralAtomAction.{u, v, w} Ty}
      {Block : Type x} {blockTypes : Block -> List Ty}
      {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
      {R : StructuralRealizer A Block blockTypes Operator L}
      (Q : StructuralLocalLaws A Block blockTypes Operator L R) :
      {source target : TypedSlotContext.{u, v} Ty} ->
      TypedSlotEmbedding source target ->
      {bound : List Ty} -> {output : Ty} ->
      StructuralForest A Block blockTypes Operator source bound output ->
      StructuralForest A Block blockTypes Operator target bound output -> Type _ where
    | nil {source target : TypedSlotContext.{u, v} Ty}
        {embedding : TypedSlotEmbedding source target}
        {bound : List Ty} {output : Ty} :
        StructuralForestDerivation Q embedding .nil .nil
    | cons {source target : TypedSlotContext.{u, v} Ty}
        {embedding : TypedSlotEmbedding source target}
        {bound : List Ty} {output : Ty}
        {leftHead : StructuralSyntax A Block blockTypes Operator source bound output}
        {rightHead : StructuralSyntax A Block blockTypes Operator target bound output}
        {leftTail : StructuralForest A Block blockTypes Operator source bound output}
        {rightTail : StructuralForest A Block blockTypes Operator target bound output}
        (head : StructuralDerivation Q embedding leftHead rightHead)
        (tail : StructuralForestDerivation Q embedding leftTail rightTail) :
        StructuralForestDerivation Q embedding
          (.cons leftHead leftTail) (.cons rightHead rightTail)
end

/-- Independent reflexive, symmetric, and transitive closure of direct
    structural derivations.  The index records the exact typed renaming:
    inversion is used for symmetry and composition for transitivity. -/
inductive StructuralAlphaClosure {Ty : Type u}
    {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R) :
    {source target : TypedSlotContext.{u, v} Ty} ->
    TypedSlotRenaming source target ->
    {bound : List Ty} -> {output : Ty} ->
    StructuralSyntax A Block blockTypes Operator source bound output ->
    StructuralSyntax A Block blockTypes Operator target bound output -> Type _ where
  | reflexive {context : TypedSlotContext.{u, v} Ty}
      {bound : List Ty} {output : Ty}
      (term : StructuralSyntax A Block blockTypes Operator context bound output) :
      StructuralAlphaClosure Q (TypedSlotRenaming.id context) term term
  | direct {source target : TypedSlotContext.{u, v} Ty}
      {alignment : TypedSlotRenaming source target}
      {bound : List Ty} {output : Ty}
      {left : StructuralSyntax A Block blockTypes Operator source bound output}
      {right : StructuralSyntax A Block blockTypes Operator target bound output}
      (derivation : StructuralDerivation Q alignment.toTypedSlotEmbedding left right) :
      StructuralAlphaClosure Q alignment left right
  | symmetric {source target : TypedSlotContext.{u, v} Ty}
      {alignment : TypedSlotRenaming source target}
      {bound : List Ty} {output : Ty}
      {left : StructuralSyntax A Block blockTypes Operator source bound output}
      {right : StructuralSyntax A Block blockTypes Operator target bound output}
      (derivation : StructuralAlphaClosure Q alignment left right) :
      StructuralAlphaClosure Q (TypedSlotRenaming.symm alignment) right left
  | transitive {source middle target : TypedSlotContext.{u, v} Ty}
      {firstRenaming : TypedSlotRenaming source middle}
      {secondRenaming : TypedSlotRenaming middle target}
      {bound : List Ty} {output : Ty}
      {left : StructuralSyntax A Block blockTypes Operator source bound output}
      {middleTerm : StructuralSyntax A Block blockTypes Operator middle bound output}
      {right : StructuralSyntax A Block blockTypes Operator target bound output}
      (first : StructuralAlphaClosure Q firstRenaming left middleTerm)
      (second : StructuralAlphaClosure Q secondRenaming middleTerm right) :
      StructuralAlphaClosure Q
        (TypedSlotRenaming.comp secondRenaming firstRenaming) left right

/-- The unindexed dependent-sum carrier required when contexts and outputs are
    data rather than fixed theorem parameters. -/
abbrev UnindexedStructuralAlphaCarrier {Ty : Type u}
    (A : StructuralAtomAction.{u, v, w} Ty)
    (Block : Type x) (blockTypes : Block -> List Ty)
    (Operator : Ty -> Type y) (bound : List Ty) :=
  Sigma fun context : TypedSlotContext.{u, v} Ty =>
    Sigma fun output : Ty =>
      StructuralSyntax A Block blockTypes Operator context bound output

/-- The unindexed relation forgets the alignment witness only after recording
    it in an indexed closure derivation. -/
inductive UnindexedStructuralAlpha {Ty : Type u}
    {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (bound : List Ty) :
    UnindexedStructuralAlphaCarrier A Block blockTypes Operator bound ->
    UnindexedStructuralAlphaCarrier A Block blockTypes Operator bound -> Prop where
  | related {source target : TypedSlotContext.{u, v} Ty} {output : Ty}
      {left : StructuralSyntax A Block blockTypes Operator source bound output}
      {right : StructuralSyntax A Block blockTypes Operator target bound output}
      (alignment : TypedSlotRenaming source target)
      (derivation : StructuralAlphaClosure Q alignment left right) :
      UnindexedStructuralAlpha Q bound
        ⟨source, ⟨output, left⟩⟩ ⟨target, ⟨output, right⟩⟩

/-- The output projection of an unindexed structural value. -/
def unindexedStructuralAlphaOutput {Ty : Type u}
    {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {bound : List Ty}
    (value : UnindexedStructuralAlphaCarrier A Block blockTypes Operator bound) : Ty :=
  value.2.1

theorem unindexedStructuralAlphaReflexive
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (bound : List Ty) :
    forall value, UnindexedStructuralAlpha Q bound value value := by
  rintro ⟨context, output, term⟩
  exact .related (TypedSlotRenaming.id context) (.reflexive term)

theorem unindexedStructuralAlphaSymmetric
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (bound : List Ty) :
    forall {left right}, UnindexedStructuralAlpha Q bound left right ->
      UnindexedStructuralAlpha Q bound right left := by
  intro left right related
  cases related with
  | related alignment derivation =>
      exact .related (TypedSlotRenaming.symm alignment) (.symmetric derivation)

theorem unindexedStructuralAlphaTransitive
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (bound : List Ty) :
    forall {left middle right},
      UnindexedStructuralAlpha Q bound left middle ->
      UnindexedStructuralAlpha Q bound middle right ->
      UnindexedStructuralAlpha Q bound left right := by
  intro left middle right first second
  cases first with
  | related firstRenaming firstDerivation =>
      cases second with
      | related secondRenaming secondDerivation =>
          exact .related
            (TypedSlotRenaming.comp secondRenaming firstRenaming)
            (.transitive firstDerivation secondDerivation)

/-- F13: the dependent-sum structural alpha relation is an equivalence, and
    related values retain the same intrinsic output type. -/
theorem indexedStructuralAlphaEquivalenceLaws
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (bound : List Ty) :
    (forall value, UnindexedStructuralAlpha Q bound value value) /\
      (forall {left right}, UnindexedStructuralAlpha Q bound left right ->
        UnindexedStructuralAlpha Q bound right left) /\
      (forall {left middle right},
        UnindexedStructuralAlpha Q bound left middle ->
        UnindexedStructuralAlpha Q bound middle right ->
        UnindexedStructuralAlpha Q bound left right) /\
      (forall {left right}, UnindexedStructuralAlpha Q bound left right ->
        unindexedStructuralAlphaOutput left =
          unindexedStructuralAlphaOutput right) := by
  refine ⟨unindexedStructuralAlphaReflexive Q bound,
    unindexedStructuralAlphaSymmetric Q bound,
    unindexedStructuralAlphaTransitive Q bound, ?_⟩
  intro left right related
  cases related
  rfl

namespace StructuralDerivation

/-- The main induction: every structural derivation is realized by a finite
    source-language certificate assembled solely from leaf and local
    constructor laws. -/
theorem certificateSoundness
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    {source target : TypedSlotContext.{u, v} Ty}
    {embedding : TypedSlotEmbedding source target}
    {bound : List Ty} {output : Ty}
    {left : StructuralSyntax A Block blockTypes Operator source bound output}
    {right : StructuralSyntax A Block blockTypes Operator target bound output}
    (item : StructuralDerivation Q embedding left right) :
    TypedEquationalCertificate L
      (L.rename embedding (R.realize left)) (R.realize right) := by
  refine StructuralDerivation.rec
    (motive_1 := fun {source target} embedding {bound output} left right _ =>
      TypedEquationalCertificate L
        (L.rename embedding (R.realize left)) (R.realize right))
    (motive_2 := fun {source target} embedding {bound output} left right _ =>
      StructuralCertificateForest L
        ((R.realizeForest left).map (fun term => L.rename embedding term))
        (R.realizeForest right))
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ item
  · intro source target embedding bound output left right step
    exact Q.atomCertificate step
  · intro source target embedding bound output kind left right children childrenIH
    have congruence := Q.containerCongruence (bound := bound) kind childrenIH
    exact TypedEquationalCertificate.rewriteLeft
      (R.containerNatural (bound := bound) embedding kind
        (R.realizeForest left)).symm congruence
  · intro source target embedding bound output boundType left right body bodyIH
    have congruence := Q.binderCongruence (bound := bound) boundType bodyIH
    exact TypedEquationalCertificate.rewriteLeft
      (R.binderNatural (bound := bound) embedding boundType
        (R.realize left)).symm congruence
  · intro source target embedding bound output descriptor left right body bodyIH
    have congruence := Q.binderBlockCongruence
      (bound := bound) descriptor bodyIH
    exact TypedEquationalCertificate.rewriteLeft
      (R.binderBlockNatural (bound := bound) embedding descriptor
        (R.realize left)).symm congruence
  · intro source target embedding bound output descriptor localLaw
      left right body bodyIH
    have congruence := Q.binderBlockAutomorphismCongruence
      (bound := bound) descriptor localLaw bodyIH
    exact TypedEquationalCertificate.rewriteLeft
      (R.binderBlockNatural (bound := bound) embedding descriptor
        (R.realize left)).symm congruence
  · intro source target embedding bound output operator left right children childrenIH
    have congruence := Q.nodeCongruence (bound := bound) operator childrenIH
    exact TypedEquationalCertificate.rewriteLeft
      (R.nodeNatural (bound := bound) embedding operator
        (R.realizeForest left)).symm congruence
  · intro x xOutput source target embedding bound output
    exact .nil
  · intro source target embedding bound output leftHead rightHead
      leftTail rightTail head tail headIH tailIH
    exact .cons headIH tailIH

end StructuralDerivation

namespace StructuralAlphaClosure

/-- Certificate soundness extends from direct structural trees to the exact
    renaming-indexed reflexive, symmetric, transitive closure. -/
theorem certificateSoundness
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    {source target : TypedSlotContext.{u, v} Ty}
    {alignment : TypedSlotRenaming source target}
    {bound : List Ty} {output : Ty}
    {left : StructuralSyntax A Block blockTypes Operator source bound output}
    {right : StructuralSyntax A Block blockTypes Operator target bound output}
    (derivation : StructuralAlphaClosure Q alignment left right) :
    TypedEquationalCertificate L
      (L.rename alignment.toTypedSlotEmbedding (R.realize left))
      (R.realize right) := by
  refine StructuralAlphaClosure.rec
    (motive := fun {source target} alignment {bound output} left right _ =>
      TypedEquationalCertificate L
        (L.rename alignment.toTypedSlotEmbedding (R.realize left))
        (R.realize right))
    ?_ ?_ ?_ ?_ derivation
  · intro context bound output term
    exact TypedEquationalCertificate.rewriteLeft
      (L.renameId (R.realize term)) (.reflexive (R.realize term))
  · intro source target innerAlignment bound output innerLeft innerRight item
    exact StructuralDerivation.certificateSoundness Q item
  · intro source target innerAlignment bound output innerLeft innerRight item itemIH
    have transported := TypedEquationalCertificate.transport
      innerAlignment.inverse (TypedEquationalCertificate.symmetric itemIH)
    have cancel :
        L.rename innerAlignment.inverse
            (L.rename innerAlignment.toTypedSlotEmbedding
              (R.realize innerLeft)) =
          R.realize innerLeft := by
      rw [L.renameComp, innerAlignment.leftInverse, L.renameId]
    exact TypedEquationalCertificate.rewriteRight transported cancel
  · intro source middle target firstRenaming secondRenaming bound output
      innerLeft middleTerm innerRight first second firstIH secondIH
    have transported := TypedEquationalCertificate.transport
      secondRenaming.toTypedSlotEmbedding firstIH
    have chained := TypedEquationalCertificate.transitive transported secondIH
    exact TypedEquationalCertificate.rewriteLeft
      (L.renameComp secondRenaming.toTypedSlotEmbedding
        firstRenaming.toTypedSlotEmbedding (R.realize innerLeft)).symm chained

end StructuralAlphaClosure

/-- F12 whole-environment encoding.  A value of this structure fixes the
    context-indexed atoms, descriptor scopes, source realization, and all
    local proof rules used by the recursive structural relation. -/
structure IndexedStructuralAlphaDefinition {Ty : Type u}
    (Block : Type x) (Operator : Ty -> Type y)
    (L : TypedTermLanguage.{u, v, z} Ty) where
  atoms : StructuralAtomAction.{u, v, w} Ty
  blockTypes : Block -> List Ty
  realizer : StructuralRealizer atoms Block blockTypes Operator L
  localLaws : StructuralLocalLaws.{u, v, w, x, y, z, r}
    atoms Block blockTypes Operator L realizer

namespace IndexedStructuralAlphaDefinition

/-- Complete recursive structural values in the packaged environment. -/
abbrev Syntax {Ty : Type u} {Block : Type x} {Operator : Ty -> Type y}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (D : TypedSlottedEGraphsPaper.IndexedStructuralAlphaDefinition.{u, v, w, x, y, z, r}
      Block Operator L)
    (context : TypedSlotContext.{u, v} Ty) (bound : List Ty) (output : Ty) :=
  StructuralSyntax D.atoms Block D.blockTypes Operator context bound output

/-- Complete structural child sequences in the packaged environment. -/
abbrev Forest {Ty : Type u} {Block : Type x} {Operator : Ty -> Type y}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (D : TypedSlottedEGraphsPaper.IndexedStructuralAlphaDefinition.{u, v, w, x, y, z, r}
      Block Operator L)
    (context : TypedSlotContext.{u, v} Ty) (bound : List Ty) (output : Ty) :=
  StructuralForest D.atoms Block D.blockTypes Operator context bound output

/-- The packaged outer-embedding action. -/
def transport {Ty : Type u} {Block : Type x} {Operator : Ty -> Type y}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (D : TypedSlottedEGraphsPaper.IndexedStructuralAlphaDefinition.{u, v, w, x, y, z, r}
      Block Operator L)
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {bound : List Ty} {output : Ty} :
    D.Syntax source bound output -> D.Syntax target bound output :=
  StructuralSyntax.act embedding

/-- The packaged unary-binder clause extends the typed de Bruijn scope. -/
def binder {Ty : Type u} {Block : Type x} {Operator : Ty -> Type y}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (D : TypedSlottedEGraphsPaper.IndexedStructuralAlphaDefinition.{u, v, w, x, y, z, r}
      Block Operator L)
    {context : TypedSlotContext.{u, v} Ty} {bound : List Ty} {output : Ty}
    (boundType : Ty) (body : D.Syntax context (boundType :: bound) output) :
    D.Syntax context bound output :=
  .binder boundType body

/-- The packaged binder-block clause extends the scope by the descriptor's
    declared type list. -/
def binderBlock {Ty : Type u} {Block : Type x} {Operator : Ty -> Type y}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (D : TypedSlottedEGraphsPaper.IndexedStructuralAlphaDefinition.{u, v, w, x, y, z, r}
      Block Operator L)
    {context : TypedSlotContext.{u, v} Ty} {bound : List Ty} {output : Ty}
    (descriptor : Block)
    (body : D.Syntax context (D.blockTypes descriptor ++ bound) output) :
    D.Syntax context bound output :=
  .binderBlock descriptor body

/-- The proof-relevant cross-context structural relation in the packaged
    environment. -/
abbrev Derivation {Ty : Type u} {Block : Type x} {Operator : Ty -> Type y}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (D : TypedSlottedEGraphsPaper.IndexedStructuralAlphaDefinition.{u, v, w, x, y, z, r}
      Block Operator L)
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {bound : List Ty} {output : Ty}
    (left : D.Syntax source bound output)
    (right : D.Syntax target bound output) :=
  StructuralDerivation D.localLaws embedding left right

end IndexedStructuralAlphaDefinition

/-- F20: semantic soundness of structural alpha reasoning, including the
    descriptor-local binder-block constructor.  Soundness follows through the
    independently constructed finite certificate. -/
theorem structuralAlphaBinderBlockSemanticSoundness
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    (M : TypedModel L)
    {source target : TypedSlotContext.{u, v} Ty}
    {alignment : TypedSlotRenaming source target}
    {bound : List Ty} {output : Ty}
    {left : StructuralSyntax A Block blockTypes Operator source bound output}
    {right : StructuralSyntax A Block blockTypes Operator target bound output}
    (derivation : StructuralAlphaClosure Q alignment left right) :
    forall environment : M.Environment target,
      M.evaluate
          (L.rename alignment.toTypedSlotEmbedding (R.realize left)) environment =
        M.evaluate (R.realize right) environment :=
  typedCertificateSemanticSoundness M
    (StructuralAlphaClosure.certificateSoundness Q derivation)

/-- F22: port/container/binder/node congruence is sound when invocation-like
    atoms carry leaf laws and binder blocks carry only descriptor-local laws. -/
theorem structuralPortAndNodeCongruenceSoundness
    {Ty : Type u} {A : StructuralAtomAction.{u, v, w} Ty}
    {Block : Type x} {blockTypes : Block -> List Ty}
    {Operator : Ty -> Type y} {L : TypedTermLanguage.{u, v, z} Ty}
    {R : StructuralRealizer A Block blockTypes Operator L}
    (Q : StructuralLocalLaws A Block blockTypes Operator L R)
    {source target : TypedSlotContext.{u, v} Ty}
    {embedding : TypedSlotEmbedding source target}
    {bound : List Ty} {output : Ty}
    {left : StructuralSyntax A Block blockTypes Operator source bound output}
    {right : StructuralSyntax A Block blockTypes Operator target bound output}
    (derivation : StructuralDerivation Q embedding left right) :
    TypedEquationalCertificate L
      (L.rename embedding (R.realize left)) (R.realize right) :=
  StructuralDerivation.certificateSoundness Q derivation

end TypedSlottedEGraphsPaper
