import TypedSlottedEGraphsPaper.Certificates
import TypedSlottedEGraphsPaper.SyntaxSupport

namespace TypedSlottedEGraphsPaper

universe u v w x y z r

/-! This file connects the concrete, schema-indexed syntax of
`SyntaxSupport` to the proof-producing structural semantics.  In particular,
containers are not collapsed to a homogeneous sequence: sequences retain
positions, bags retain occurrence tokens, and sets use two-sided mates. -/

/-- A finite bijection, kept local so the adapter does not rely on a quotient
or on decidable equality of container elements. -/
structure FiniteBijection (left right : Nat) where
  toFun : Fin left -> Fin right
  invFun : Fin right -> Fin left
  leftInverse : forall i, invFun (toFun i) = i
  rightInverse : forall i, toFun (invFun i) = i

/-- The unique order-preserving token matching used by sequences.  Requiring
equal numeric positions entails equal lengths without equating proof fields. -/
structure PositionBijection (left right : Nat)
    extends FiniteBijection left right where
  preservesPosition : forall i, (toFiniteBijection.toFun i).val = i.val

namespace FiniteBijection

def id (size : Nat) : FiniteBijection size size where
  toFun := fun i => i
  invFun := fun i => i
  leftInverse := by intro i; rfl
  rightInverse := by intro i; rfl

def symm {left right : Nat} (bijection : FiniteBijection left right) :
    FiniteBijection right left where
  toFun := bijection.invFun
  invFun := bijection.toFun
  leftInverse := bijection.rightInverse
  rightInverse := bijection.leftInverse

def comp {first second third : Nat}
    (outer : FiniteBijection second third)
    (inner : FiniteBijection first second) : FiniteBijection first third where
  toFun := fun i => outer.toFun (inner.toFun i)
  invFun := fun i => inner.invFun (outer.invFun i)
  leftInverse := by
    intro i
    rw [outer.leftInverse, inner.leftInverse]
  rightInverse := by
    intro i
    rw [inner.rightInverse, outer.rightInverse]

end FiniteBijection

/-- A type-preserving permutation of the currently bound de Bruijn scope. -/
structure TypedBoundPermutation {Ty : Type u} (bound : List Ty) where
  bijection : FiniteBijection bound.length bound.length
  preservesType : forall i, bound.get (bijection.toFun i) = bound.get i

namespace TypedBoundPermutation

/-- The identity bound-scope alignment. -/
def id {Ty : Type u} (bound : List Ty) : TypedBoundPermutation bound where
  bijection := {
    toFun := fun i => i
    invFun := fun i => i
    leftInverse := by intro i; rfl
    rightInverse := by intro i; rfl
  }
  preservesType := by intro i; rfl

end TypedBoundPermutation

/-- Evidence that a unary binder fixes its new head variable and extends the
existing bound-scope permutation on the tail. -/
structure UnaryScopeExtension {Ty : Type u} (boundType : Ty)
    {bound : List Ty} (outer : TypedBoundPermutation bound)
    (inner : TypedBoundPermutation (boundType :: bound)) : Prop where
  headFixed : inner.bijection.toFun 0 = 0
  tailAction : forall i : Fin bound.length,
    inner.bijection.toFun i.succ = (outer.bijection.toFun i).succ

/-- A descriptor block acts by a typed permutation of its declared prefix
and by the already selected alignment on the surrounding bound scope.  The
prefix bijection is the proof-relevant descriptor automorphism. -/
def descriptorPrefixIndex {Ty : Type u} (descriptorTypes bound : List Ty)
    (i : Fin descriptorTypes.length) :
    Fin (descriptorTypes ++ bound).length :=
  Fin.cast List.length_append.symm (Fin.castAdd bound.length i)

def descriptorTailIndex {Ty : Type u} (descriptorTypes bound : List Ty)
    (i : Fin bound.length) : Fin (descriptorTypes ++ bound).length :=
  Fin.cast List.length_append.symm (Fin.natAdd descriptorTypes.length i)

structure DescriptorScopeExtension {Ty : Type u} (descriptorTypes : List Ty)
    {bound : List Ty} (outer : TypedBoundPermutation bound)
    (inner : TypedBoundPermutation (descriptorTypes ++ bound)) where
  descriptorAutomorphism :
    FiniteBijection descriptorTypes.length descriptorTypes.length
  prefixAction : forall i : Fin descriptorTypes.length,
    inner.bijection.toFun (descriptorPrefixIndex descriptorTypes bound i) =
      descriptorPrefixIndex descriptorTypes bound
        (descriptorAutomorphism.toFun i)
  tailAction : forall i : Fin bound.length,
    inner.bijection.toFun (descriptorTailIndex descriptorTypes bound i) =
      descriptorTailIndex descriptorTypes bound (outer.bijection.toFun i)

/-- The signature's declared binder-block automorphism subgroup. -/
structure DescriptorAutomorphismPolicy
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op) where
  Admissible : (descriptor : Descriptor) ->
    FiniteBijection (signature.boundTypes descriptor).length
      (signature.boundTypes descriptor).length -> Prop
  identityAdmissible : forall descriptor,
    Admissible descriptor (FiniteBijection.id _)
  inverseAdmissible : forall {descriptor} {permutation},
    Admissible descriptor permutation ->
      Admissible descriptor (FiniteBijection.symm permutation)
  compositionAdmissible : forall {descriptor} {first second},
    Admissible descriptor first -> Admissible descriptor second ->
      Admissible descriptor (FiniteBijection.comp second first)

/-- A scope extension whose prefix permutation is certified to belong to the
descriptor's declared automorphism subgroup. -/
structure AdmissibleDescriptorScopeExtension
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    (descriptor : Descriptor) {bound : List Ty}
    (outer : TypedBoundPermutation bound)
    (inner : TypedBoundPermutation (signature.boundTypes descriptor ++ bound)) :
    Type _ extends DescriptorScopeExtension
      (signature.boundTypes descriptor) outer inner where
  admissible : policy.Admissible descriptor
    toDescriptorScopeExtension.descriptorAutomorphism

namespace PortSchema

/-- Every recursive port schema ultimately has one intrinsic result type. -/
@[simp] def resultType {Ty : Type u} {Descriptor : Type x} :
    PortSchema Ty Descriptor -> Ty
  | .one output => output
  | .container _ _ element => resultType element
  | .bind _ body => resultType body
  | .bindBlock _ body => resultType body

end PortSchema

namespace ConcretePorts

/-- Lookup by an expanded occurrence token.  Bag multiplicity is represented
by distinct indices even when two stored elements are syntactically equal. -/
def get {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
    {schema : PortSchema Ty Descriptor} {size : Nat} :
    ConcretePorts signature context bound schema size -> Fin size ->
      ConcretePort signature context bound schema
  | .cons head tail, index => Fin.cases head (fun i => get tail i) index

end ConcretePorts

/-- Heterogeneous source arguments: every position has the result type of its
own port schema. -/
inductive ConcreteSourceArguments {Ty : Type u} {Descriptor : Type x}
    (L : TypedTermLanguage.{u, v, z} Ty)
    (context : TypedSlotContext.{u, v} Ty) :
    List (PortSchema Ty Descriptor) -> Type _ where
  | nil : ConcreteSourceArguments L context []
  | cons {schema : PortSchema Ty Descriptor}
      {schemas : List (PortSchema Ty Descriptor)}
      (head : L.Term context schema.resultType)
      (tail : ConcreteSourceArguments L context schemas) :
      ConcreteSourceArguments L context (schema :: schemas)

namespace ConcreteSourceArguments

/-- Componentwise outer-context transport of heterogeneous source arguments. -/
def rename {Ty : Type u} {Descriptor : Type x}
    {L : TypedTermLanguage.{u, v, z} Ty}
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) :
    {schemas : List (PortSchema Ty Descriptor)} ->
    ConcreteSourceArguments L source schemas ->
      ConcreteSourceArguments L target schemas
  | _, .nil => .nil
  | _, .cons head tail => .cons (L.rename embedding head) (rename embedding tail)

end ConcreteSourceArguments

set_option linter.unusedVariables false in
/-- A concrete structural realizer.  Containers receive their expanded
occurrence family, so sequence positions, bag multiplicities, and set inputs
remain available to the licensed source constructor. -/
structure ConcreteStructuralRealizer
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    (L : TypedTermLanguage.{u, v, z} Ty) where
  atom : {context : TypedSlotContext.{u, v} Ty} -> {bound : List Ty} ->
    {output : Ty} -> ScopedPortAtom signature context bound output ->
      L.Term context output
  container : {context : TypedSlotContext.{u, v} Ty} -> {bound : List Ty} ->
    {output : Ty} -> ContainerKind -> (size : Nat) ->
    (Fin size -> L.Term context output) -> L.Term context output
  binder : {context : TypedSlotContext.{u, v} Ty} -> {bound : List Ty} ->
    {output : Ty} -> (boundType : Ty) -> L.Term context output ->
      L.Term context output
  binderBlock : {context : TypedSlotContext.{u, v} Ty} ->
    {bound : List Ty} -> {output : Ty} -> (descriptor : Descriptor) ->
    L.Term context output -> L.Term context output
  node : {context : TypedSlotContext.{u, v} Ty} -> (operator : Op) ->
    ConcreteSourceArguments L context (signature.inputSchemas operator) ->
      L.Term context (signature.outputType operator)

namespace ConcreteStructuralRealizer

mutual
  /-- Realization of a schema-indexed concrete port. -/
  def realizePort
      {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
      {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
        Ty Descriptor ClassId Op}
      {L : TypedTermLanguage.{u, v, z} Ty}
      (R : ConcreteStructuralRealizer signature L)
      {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
      {schema : PortSchema Ty Descriptor} :
      ConcretePort signature context bound schema ->
        L.Term context schema.resultType
    | .atom value => R.atom value
    | .container (kind := kind) (element := element) (size := size) values _ =>
        R.container (bound := bound) kind size (fun i =>
          realizeOccurrence (schema := element) (size := size) R values i)
    | .bind (boundType := boundType) (body := body) value =>
        R.binder (bound := bound) boundType
          (realizePort (schema := body) R value)
    | .bindBlock (descriptor := descriptor) (body := body) value =>
        R.binderBlock (bound := bound) descriptor
          (realizePort (schema := body) R value)

  /-- Realization at one expanded occurrence token. -/
  def realizeOccurrence
      {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
      {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
        Ty Descriptor ClassId Op}
      {L : TypedTermLanguage.{u, v, z} Ty}
      (R : ConcreteStructuralRealizer signature L)
      {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
      {schema : PortSchema Ty Descriptor} {size : Nat}
      (values : ConcretePorts signature context bound schema size)
      (index : Fin size) : L.Term context schema.resultType :=
    realizePort R (ConcretePorts.get values index)
end

/-- Realization of a heterogeneous signature argument tuple. -/
def realizeArguments
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (R : ConcreteStructuralRealizer signature L)
    {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
    {schemas : List (PortSchema Ty Descriptor)} :
    ConcreteArguments signature context bound schemas ->
      ConcreteSourceArguments L context schemas
  | .nil => .nil
  | .cons head tail => .cons (realizePort R head) (realizeArguments R tail)

/-- Realization of a concrete node with its signature-selected output type. -/
def realizeNode
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (R : ConcreteStructuralRealizer signature L)
    {context : TypedSlotContext.{u, v} Ty} {output : Ty} :
    ConcreteFlexibleArityENode signature context output -> L.Term context output
  | .make operator arguments => R.node operator (realizeArguments R arguments)

end ConcreteStructuralRealizer

/-- Exact local atom alignment for the paper's typed alpha relation.  Free
slots follow the outer embedding, local variables follow the current typed
bound permutation, and invocations retain their identifier while composing
their interface embedding. -/
inductive ConcreteAlphaAtomStep
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {bound : List Ty} (scope : TypedBoundPermutation bound) :
    {output : Ty} -> ScopedPortAtom signature source bound output ->
      ScopedPortAtom signature target bound output -> Prop where
  | free {output : Ty} (left : source.Slot) (leftTyped : source.typeOf left = output)
      (right : target.Slot) (rightTyped : target.typeOf right = output)
      (mapped : embedding.toFun left = right) :
      ConcreteAlphaAtomStep embedding scope
        (.free left leftTyped) (.free right rightTyped)
  | boundVar {output : Ty} (left : Fin bound.length)
      (leftTyped : bound.get left = output) (right : Fin bound.length)
      (rightTyped : bound.get right = output)
      (mapped : scope.bijection.toFun left = right) :
      ConcreteAlphaAtomStep embedding scope
        (.boundVar left leftTyped) (.boundVar right rightTyped)
  | invoke (classId : ClassId)
      (left : TypedSlotEmbedding (signature.classInterface classId) source)
      (right : TypedSlotEmbedding (signature.classInterface classId) target)
      (mapped : TypedSlotEmbedding.comp embedding left = right) :
      ConcreteAlphaAtomStep embedding scope
        (.invoke classId left) (.invoke classId right)

/- The alignment is defined by structural recursion on the schema.  Recursive
premises are only alignments at strict subschemas; no clause accepts a proof
about the complete parent endpoints. -/
def ConcretePortAlignment
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    (AtomStep : {source target : TypedSlotContext.{u, v} Ty} ->
      (embedding : TypedSlotEmbedding source target) ->
      {bound : List Ty} -> (scope : TypedBoundPermutation bound) ->
      {output : Ty} -> ScopedPortAtom signature source bound output ->
        ScopedPortAtom signature target bound output -> Prop)
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {bound : List Ty} (scope : TypedBoundPermutation bound)
    {schema : PortSchema Ty Descriptor}
    (left : ConcretePort signature source bound schema)
    (right : ConcretePort signature target bound schema) : Prop :=
  match left, right with
  | .atom leftAtom, .atom rightAtom => AtomStep embedding scope leftAtom rightAtom
  | .container (kind := .seq) (size := leftSize) leftValues _,
      .container (size := rightSize) rightValues _ =>
      Exists fun tokens : PositionBijection leftSize rightSize =>
        (i : Fin leftSize) -> ConcretePortAlignment policy AtomStep embedding scope
          (ConcretePorts.get leftValues i)
          (ConcretePorts.get rightValues (tokens.toFiniteBijection.toFun i))
  | .container (kind := .bag) (size := leftSize) leftValues _,
      .container (size := rightSize) rightValues _ =>
      Exists fun tokens : FiniteBijection leftSize rightSize =>
        (i : Fin leftSize) -> ConcretePortAlignment policy AtomStep embedding scope
          (ConcretePorts.get leftValues i)
          (ConcretePorts.get rightValues (tokens.toFun i))
  | .container (kind := .set) (size := leftSize) leftValues _,
      .container (size := rightSize) rightValues _ =>
      Exists fun forwardMate : Fin leftSize -> Fin rightSize =>
      Exists fun backwardMate : Fin rightSize -> Fin leftSize =>
        ((i : Fin leftSize) -> ConcretePortAlignment policy AtomStep embedding scope
          (ConcretePorts.get leftValues i)
          (ConcretePorts.get rightValues (forwardMate i)))
        ∧
        ((j : Fin rightSize) -> ConcretePortAlignment policy AtomStep embedding scope
          (ConcretePorts.get leftValues (backwardMate j))
          (ConcretePorts.get rightValues j))
  | .bind (boundType := boundType) leftBody, .bind rightBody =>
      Exists fun innerScope : TypedBoundPermutation (boundType :: bound) =>
      Exists fun _ : UnaryScopeExtension boundType scope innerScope =>
        ConcretePortAlignment policy AtomStep embedding innerScope leftBody rightBody
  | .bindBlock (descriptor := descriptor) leftBody, .bindBlock rightBody =>
      Exists fun innerScope : TypedBoundPermutation
        (signature.boundTypes descriptor ++ bound) =>
      Exists fun _ : AdmissibleDescriptorScopeExtension
        policy descriptor scope innerScope =>
        ConcretePortAlignment policy AtomStep embedding innerScope leftBody rightBody
termination_by schema

/-- Pointwise alignment of a heterogeneous signature tuple. -/
def ConcreteArgumentsAlignment
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    (AtomStep : {source target : TypedSlotContext.{u, v} Ty} ->
      (embedding : TypedSlotEmbedding source target) ->
      {bound : List Ty} -> (scope : TypedBoundPermutation bound) ->
      {output : Ty} -> ScopedPortAtom signature source bound output ->
        ScopedPortAtom signature target bound output -> Prop)
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {bound : List Ty} (scope : TypedBoundPermutation bound)
    {schemas : List (PortSchema Ty Descriptor)}
    (left : ConcreteArguments signature source bound schemas)
    (right : ConcreteArguments signature target bound schemas) : Prop :=
  match left, right with
  | .nil, .nil => PUnit
  | .cons leftHead leftTail, .cons rightHead rightTail =>
      ConcretePortAlignment policy AtomStep embedding scope leftHead rightHead ∧
        ConcreteArgumentsAlignment policy AtomStep embedding scope leftTail rightTail
termination_by schemas

/-- Node alignment fixes the operator (and hence its heterogeneous signature
and output type) and recursively aligns every declared port. -/
inductive ConcreteNodeAlignment
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    (AtomStep : {source target : TypedSlotContext.{u, v} Ty} ->
      (embedding : TypedSlotEmbedding source target) ->
      {bound : List Ty} -> (scope : TypedBoundPermutation bound) ->
      {output : Ty} -> ScopedPortAtom signature source bound output ->
        ScopedPortAtom signature target bound output -> Prop)
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) :
    {output : Ty} -> ConcreteFlexibleArityENode signature source output ->
      ConcreteFlexibleArityENode signature target output -> Prop where
  | make (operator : Op)
      {left : ConcreteArguments signature source []
        (signature.inputSchemas operator)}
      {right : ConcreteArguments signature target []
        (signature.inputSchemas operator)}
      (arguments : ConcreteArgumentsAlignment policy AtomStep embedding
        (TypedBoundPermutation.id []) left right) :
      ConcreteNodeAlignment policy AtomStep embedding
        (.make operator left) (.make operator right)

/-- The direct, one-pass structural alpha generator for port values. -/
abbrev ConcreteDirectTypedAlphaPort
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    {source target : TypedSlotContext.{u, v} Ty}
    (alignment : TypedSlotRenaming source target)
    {schema : PortSchema Ty Descriptor}
    (left : ConcretePort.Value signature source schema)
    (right : ConcretePort.Value signature target schema) :=
  ConcretePortAlignment policy ConcreteAlphaAtomStep
    alignment.toTypedSlotEmbedding (TypedBoundPermutation.id []) left right

/-- The direct, one-pass structural alpha generator for heterogeneous nodes. -/
abbrev ConcreteDirectTypedAlphaNode
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    {source target : TypedSlotContext.{u, v} Ty}
    (alignment : TypedSlotRenaming source target) {output : Ty}
    (left : ConcreteFlexibleArityENode signature source output)
    (right : ConcreteFlexibleArityENode signature target output) :=
  ConcreteNodeAlignment policy ConcreteAlphaAtomStep
    alignment.toTypedSlotEmbedding left right

/-- F12's renaming-indexed alpha judgement: the reflexive, symmetric, and
transitive closure of the concrete recursive structural generators. -/
inductive ConcreteAlphaPortClosure
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature) :
    {source target : TypedSlotContext.{u, v} Ty} ->
    TypedSlotRenaming source target -> {schema : PortSchema Ty Descriptor} ->
    ConcretePort.Value signature source schema ->
    ConcretePort.Value signature target schema -> Prop where
  | reflexive {context schema}
      (port : ConcretePort.Value signature context schema) :
      ConcreteAlphaPortClosure policy (TypedSlotRenaming.id context) port port
  | direct {source target schema} {alignment : TypedSlotRenaming source target}
      {left : ConcretePort.Value signature source schema}
      {right : ConcretePort.Value signature target schema}
      (derivation : ConcreteDirectTypedAlphaPort policy alignment left right) :
      ConcreteAlphaPortClosure policy alignment left right
  | symmetric {source target schema}
      {alignment : TypedSlotRenaming source target}
      {left : ConcretePort.Value signature source schema}
      {right : ConcretePort.Value signature target schema}
      (derivation : ConcreteAlphaPortClosure policy alignment left right) :
      ConcreteAlphaPortClosure policy (TypedSlotRenaming.symm alignment) right left
  | transitive {source middle target schema}
      {firstRenaming : TypedSlotRenaming source middle}
      {secondRenaming : TypedSlotRenaming middle target}
      {left : ConcretePort.Value signature source schema}
      {middlePort : ConcretePort.Value signature middle schema}
      {right : ConcretePort.Value signature target schema}
      (first : ConcreteAlphaPortClosure policy firstRenaming left middlePort)
      (second : ConcreteAlphaPortClosure policy secondRenaming middlePort right) :
      ConcreteAlphaPortClosure policy
        (TypedSlotRenaming.comp secondRenaming firstRenaming) left right

/-- F12/F13 node judgement with the same renaming-indexed closure. -/
inductive ConcreteAlphaNodeClosure
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature) :
    {source target : TypedSlotContext.{u, v} Ty} ->
    TypedSlotRenaming source target -> {output : Ty} ->
    ConcreteFlexibleArityENode signature source output ->
    ConcreteFlexibleArityENode signature target output -> Prop where
  | reflexive {context output}
      (node : ConcreteFlexibleArityENode signature context output) :
      ConcreteAlphaNodeClosure policy (TypedSlotRenaming.id context) node node
  | direct {source target output} {alignment : TypedSlotRenaming source target}
      {left : ConcreteFlexibleArityENode signature source output}
      {right : ConcreteFlexibleArityENode signature target output}
      (derivation : ConcreteDirectTypedAlphaNode policy alignment left right) :
      ConcreteAlphaNodeClosure policy alignment left right
  | symmetric {source target output}
      {alignment : TypedSlotRenaming source target}
      {left : ConcreteFlexibleArityENode signature source output}
      {right : ConcreteFlexibleArityENode signature target output}
      (derivation : ConcreteAlphaNodeClosure policy alignment left right) :
      ConcreteAlphaNodeClosure policy (TypedSlotRenaming.symm alignment) right left
  | transitive {source middle target output}
      {firstRenaming : TypedSlotRenaming source middle}
      {secondRenaming : TypedSlotRenaming middle target}
      {left : ConcreteFlexibleArityENode signature source output}
      {middleNode : ConcreteFlexibleArityENode signature middle output}
      {right : ConcreteFlexibleArityENode signature target output}
      (first : ConcreteAlphaNodeClosure policy firstRenaming left middleNode)
      (second : ConcreteAlphaNodeClosure policy secondRenaming middleNode right) :
      ConcreteAlphaNodeClosure policy
        (TypedSlotRenaming.comp secondRenaming firstRenaming) left right

/-- Public F12 port judgement. -/
abbrev ConcreteTypedAlphaPort := @ConcreteAlphaPortClosure

/-- Public F12 node judgement. -/
abbrev ConcreteTypedAlphaNode := @ConcreteAlphaNodeClosure

/-- F13 indexed identity, inverse, and composition laws for ports. -/
theorem concreteTypedAlphaEquivalenceLaws
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    {source middle target : TypedSlotContext.{u, v} Ty}
    {schema : PortSchema Ty Descriptor}
    {firstRenaming : TypedSlotRenaming source middle}
    {secondRenaming : TypedSlotRenaming middle target}
    {left : ConcretePort.Value signature source schema}
    {middlePort : ConcretePort.Value signature middle schema}
    {right : ConcretePort.Value signature target schema}
    (first : ConcreteTypedAlphaPort policy firstRenaming left middlePort)
    (second : ConcreteTypedAlphaPort policy secondRenaming middlePort right) :
    ConcreteTypedAlphaPort policy (TypedSlotRenaming.id source) left left /\
      ConcreteTypedAlphaPort policy (TypedSlotRenaming.symm firstRenaming)
        middlePort left /\
      ConcreteTypedAlphaPort policy
        (TypedSlotRenaming.comp secondRenaming firstRenaming) left right :=
  ⟨.reflexive left, .symmetric first, .transitive first second⟩

/-- F13 indexed identity, inverse, composition, and output preservation for
heterogeneous nodes.  Output preservation is intrinsic in the common index. -/
theorem concreteTypedAlphaNodeEquivalenceLaws
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    {source middle target : TypedSlotContext.{u, v} Ty} {output : Ty}
    {firstRenaming : TypedSlotRenaming source middle}
    {secondRenaming : TypedSlotRenaming middle target}
    {left : ConcreteFlexibleArityENode signature source output}
    {middleNode : ConcreteFlexibleArityENode signature middle output}
    {right : ConcreteFlexibleArityENode signature target output}
    (first : ConcreteTypedAlphaNode policy firstRenaming left middleNode)
    (second : ConcreteTypedAlphaNode policy secondRenaming middleNode right) :
    ConcreteTypedAlphaNode policy (TypedSlotRenaming.id source) left left /\
      ConcreteTypedAlphaNode policy (TypedSlotRenaming.symm firstRenaming)
        middleNode left /\
      ConcreteTypedAlphaNode policy
        (TypedSlotRenaming.comp secondRenaming firstRenaming) left right /\
      ConcreteFlexibleArityENode.output left =
        ConcreteFlexibleArityENode.output right :=
  ⟨.reflexive left, .symmetric first, .transitive first second, rfl⟩

/-- Dependent-pair carrier obtained by forgetting a port's outer context. -/
abbrev ConcreteUnindexedPortCarrier
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    (schema : PortSchema Ty Descriptor) :=
  Sigma fun context : TypedSlotContext.{u, v} Ty =>
    ConcretePort.Value signature context schema

/-- The unindexed port relation existentially retains its typed renaming. -/
def ConcreteUnindexedAlphaPort
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    {schema : PortSchema Ty Descriptor}
    (left right : ConcreteUnindexedPortCarrier signature schema) : Prop :=
  match left, right with
  | ⟨source, leftPort⟩, ⟨target, rightPort⟩ =>
      ∃ alignment : TypedSlotRenaming source target,
        ConcreteTypedAlphaPort policy alignment leftPort rightPort

/-- F13's dependent-pair unindexed relation is reflexive, symmetric, and
transitive. -/
theorem concreteUnindexedAlphaPortEquivalenceLaws
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    (schema : PortSchema Ty Descriptor) :
    (forall value : ConcreteUnindexedPortCarrier signature schema,
      ConcreteUnindexedAlphaPort policy value value) /\
    (forall {left right : ConcreteUnindexedPortCarrier signature schema},
      ConcreteUnindexedAlphaPort policy left right ->
        ConcreteUnindexedAlphaPort policy right left) /\
    (forall {left middle right : ConcreteUnindexedPortCarrier signature schema},
      ConcreteUnindexedAlphaPort policy left middle ->
      ConcreteUnindexedAlphaPort policy middle right ->
        ConcreteUnindexedAlphaPort policy left right) := by
  refine ⟨?_, ?_, ?_⟩
  · rintro ⟨context, port⟩
    exact ⟨TypedSlotRenaming.id context, .reflexive port⟩
  · rintro ⟨source, leftPort⟩ ⟨target, rightPort⟩
    rintro ⟨alignment, derivation⟩
    exact ⟨TypedSlotRenaming.symm alignment, .symmetric derivation⟩
  · rintro ⟨source, leftPort⟩ ⟨middle, middlePort⟩
      ⟨target, rightPort⟩
    rintro ⟨firstRenaming, first⟩ ⟨secondRenaming, second⟩
    exact ⟨TypedSlotRenaming.comp secondRenaming firstRenaming,
      .transitive first second⟩

/-- Whole F13 package: independently quantified indexed groupoid laws and the
    induced unindexed equivalence.  No law is hidden behind evidence for a
    different law. -/
theorem concreteTypedAlphaFullEquivalenceLaws
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    (policy : DescriptorAutomorphismPolicy signature)
    (schema : PortSchema Ty Descriptor) :
    (∀ {context : TypedSlotContext.{u, v} Ty}
      (value : ConcretePort.Value signature context schema),
      ConcreteTypedAlphaPort policy (TypedSlotRenaming.id context) value value) /\
    (∀ {source target : TypedSlotContext.{u, v} Ty}
      {alignment : TypedSlotRenaming source target}
      {left : ConcretePort.Value signature source schema}
      {right : ConcretePort.Value signature target schema},
      ConcreteTypedAlphaPort policy alignment left right ->
        ConcreteTypedAlphaPort policy (TypedSlotRenaming.symm alignment)
          right left) /\
    (∀ {source middle target : TypedSlotContext.{u, v} Ty}
      {firstRenaming : TypedSlotRenaming source middle}
      {secondRenaming : TypedSlotRenaming middle target}
      {left : ConcretePort.Value signature source schema}
      {middlePort : ConcretePort.Value signature middle schema}
      {right : ConcretePort.Value signature target schema},
      ConcreteTypedAlphaPort policy firstRenaming left middlePort ->
      ConcreteTypedAlphaPort policy secondRenaming middlePort right ->
        ConcreteTypedAlphaPort policy
          (TypedSlotRenaming.comp secondRenaming firstRenaming) left right) /\
    ((forall value : ConcreteUnindexedPortCarrier signature schema,
      ConcreteUnindexedAlphaPort policy value value) /\
    (forall {unindexedLeft unindexedRight :
        ConcreteUnindexedPortCarrier signature schema},
      ConcreteUnindexedAlphaPort policy unindexedLeft unindexedRight ->
        ConcreteUnindexedAlphaPort policy unindexedRight unindexedLeft) /\
    (forall {unindexedLeft unindexedMiddle unindexedRight :
        ConcreteUnindexedPortCarrier signature schema},
      ConcreteUnindexedAlphaPort policy unindexedLeft unindexedMiddle ->
      ConcreteUnindexedAlphaPort policy unindexedMiddle unindexedRight ->
        ConcreteUnindexedAlphaPort policy unindexedLeft unindexedRight)) := by
  refine ⟨?_, ?_, ?_, concreteUnindexedAlphaPortEquivalenceLaws policy schema⟩
  · exact fun value => .reflexive value
  · exact fun derivation => .symmetric derivation
  · exact fun first second => .transitive first second

/-- Componentwise certificates between heterogeneous realized arguments. -/
inductive ConcreteArgumentCertificates
    {Ty : Type u} {Descriptor : Type x}
    (L : TypedTermLanguage.{u, v, z} Ty)
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) :
    {schemas : List (PortSchema Ty Descriptor)} ->
    ConcreteSourceArguments L source schemas ->
    ConcreteSourceArguments L target schemas -> Prop where
  | nil : ConcreteArgumentCertificates L embedding .nil .nil
  | cons (head : TypedEquationalCertificate L (L.rename embedding left) right)
      (tail : ConcreteArgumentCertificates L embedding lefts rights) :
      ConcreteArgumentCertificates L embedding
        (.cons left lefts) (.cons right rights)

/-- The licensed one-constructor proof rules.  Every premise is a child
certificate; none is a certificate for the complete parent endpoints. -/
structure ConcreteConstructorLaws
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (R : ConcreteStructuralRealizer signature L)
    (policy : DescriptorAutomorphismPolicy signature) where
  sequenceCongruence : forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {bound : List Ty}
    {output : Ty} {leftSize rightSize : Nat}
    (left : Fin leftSize -> L.Term source output)
    (right : Fin rightSize -> L.Term target output)
    (tokens : PositionBijection leftSize rightSize),
    (forall i, TypedEquationalCertificate L
      (L.rename embedding (left i))
      (right (tokens.toFiniteBijection.toFun i))) ->
    TypedEquationalCertificate L
      (L.rename embedding (R.container (bound := bound) .seq leftSize left))
      (R.container (bound := bound) .seq rightSize right)
  bagCongruence : forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {bound : List Ty}
    {output : Ty} {leftSize rightSize : Nat}
    (left : Fin leftSize -> L.Term source output)
    (right : Fin rightSize -> L.Term target output)
    (tokens : FiniteBijection leftSize rightSize),
    (forall i, TypedEquationalCertificate L
      (L.rename embedding (left i)) (right (tokens.toFun i))) ->
    TypedEquationalCertificate L
      (L.rename embedding (R.container (bound := bound) .bag leftSize left))
      (R.container (bound := bound) .bag rightSize right)
  setCongruence : forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {bound : List Ty}
    {output : Ty} {leftSize rightSize : Nat}
    (left : Fin leftSize -> L.Term source output)
    (right : Fin rightSize -> L.Term target output)
    (forwardMate : Fin leftSize -> Fin rightSize)
    (backwardMate : Fin rightSize -> Fin leftSize),
    (forall i, TypedEquationalCertificate L
      (L.rename embedding (left i)) (right (forwardMate i))) ->
    (forall j, TypedEquationalCertificate L
      (L.rename embedding (left (backwardMate j))) (right j)) ->
    TypedEquationalCertificate L
      (L.rename embedding (R.container (bound := bound) .set leftSize left))
      (R.container (bound := bound) .set rightSize right)
  binderCongruence : forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {bound : List Ty}
    {output : Ty} (boundType : Ty)
    (outer : TypedBoundPermutation bound)
    (inner : TypedBoundPermutation (boundType :: bound)),
    UnaryScopeExtension boundType outer inner ->
    {left : L.Term source output} -> {right : L.Term target output} ->
    TypedEquationalCertificate L (L.rename embedding left) right ->
    TypedEquationalCertificate L
      (L.rename embedding (R.binder (bound := bound) boundType left))
      (R.binder (bound := bound) boundType right)
  binderBlockCongruence :
    forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {bound : List Ty}
    {output : Ty} (descriptor : Descriptor)
    (outer : TypedBoundPermutation bound)
    (inner : TypedBoundPermutation (signature.boundTypes descriptor ++ bound)),
    AdmissibleDescriptorScopeExtension policy descriptor outer inner ->
    {left : L.Term source output} -> {right : L.Term target output} ->
    TypedEquationalCertificate L (L.rename embedding left) right ->
    TypedEquationalCertificate L
      (L.rename embedding (R.binderBlock (bound := bound) descriptor left))
      (R.binderBlock (bound := bound) descriptor right)
  nodeCongruence : forall {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) (operator : Op)
    {left : ConcreteSourceArguments L source (signature.inputSchemas operator)}
    {right : ConcreteSourceArguments L target (signature.inputSchemas operator)},
    ConcreteArgumentCertificates L embedding left right ->
    TypedEquationalCertificate L
      (L.rename embedding (R.node operator left)) (R.node operator right)

/-- Constructor laws plus the independently checked local atom rule. -/
structure ConcreteStructuralLaws
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (R : ConcreteStructuralRealizer signature L)
    (policy : DescriptorAutomorphismPolicy signature)
    (AtomStep : {source target : TypedSlotContext.{u, v} Ty} ->
      (embedding : TypedSlotEmbedding source target) ->
      {bound : List Ty} -> (scope : TypedBoundPermutation bound) ->
      {output : Ty} -> ScopedPortAtom signature source bound output ->
        ScopedPortAtom signature target bound output -> Prop)
    : Type _ extends ConcreteConstructorLaws R policy where
  atomCertificate : forall {source target : TypedSlotContext.{u, v} Ty}
    {embedding : TypedSlotEmbedding source target} {bound : List Ty}
    {scope : TypedBoundPermutation bound} {output : Ty}
    {left : ScopedPortAtom signature source bound output}
    {right : ScopedPortAtom signature target bound output},
    AtomStep embedding scope left right ->
    TypedEquationalCertificate L
      (L.rename embedding (R.atom left)) (R.atom right)

namespace ConcretePortAlignment

  /-- Structural certificate soundness for concrete ports, proved by the
  schema recursion. -/
  theorem certificateSoundness
      {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
      {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
        Ty Descriptor ClassId Op}
      {L : TypedTermLanguage.{u, v, z} Ty}
      {R : ConcreteStructuralRealizer signature L}
      {policy : DescriptorAutomorphismPolicy signature}
      {AtomStep : {source target : TypedSlotContext.{u, v} Ty} ->
        (embedding : TypedSlotEmbedding source target) ->
        {bound : List Ty} -> (scope : TypedBoundPermutation bound) ->
        {output : Ty} -> ScopedPortAtom signature source bound output ->
          ScopedPortAtom signature target bound output -> Prop}
      (laws : ConcreteStructuralLaws R policy AtomStep)
      {source target : TypedSlotContext.{u, v} Ty}
      {embedding : TypedSlotEmbedding source target}
      {bound : List Ty} {scope : TypedBoundPermutation bound}
      {schema : PortSchema Ty Descriptor}
      {left : ConcretePort signature source bound schema}
      {right : ConcretePort signature target bound schema}
      (derivation : ConcretePortAlignment policy AtomStep embedding scope left right) :
      TypedEquationalCertificate L
        (L.rename embedding (R.realizePort left)) (R.realizePort right) := by
    induction schema generalizing source target bound with
    | one output =>
        cases left with
        | atom leftAtom =>
          cases right with
          | atom rightAtom =>
            simpa only [PortSchema.resultType,
              ConcreteStructuralRealizer.realizePort] using
              laws.atomCertificate
                (by simpa only [PortSchema.resultType, ConcretePortAlignment]
                  using derivation)
    | container kind arity element elementIH =>
        cases left with
        | container leftValues leftLicensed =>
          cases right with
          | container rightValues rightLicensed =>
            cases kind with
            | seq =>
                simp only [ConcretePortAlignment] at derivation
                rcases derivation with ⟨tokens, items⟩
                simpa only [PortSchema.resultType,
                  ConcreteStructuralRealizer.realizePort] using
                  laws.sequenceCongruence embedding
                  (fun i => R.realizeOccurrence leftValues i)
                  (fun i => R.realizeOccurrence rightValues i) tokens
                  (fun i => by
                    simpa only [ConcreteStructuralRealizer.realizeOccurrence]
                      using elementIH (derivation := items i))
            | bag =>
                simp only [ConcretePortAlignment] at derivation
                rcases derivation with ⟨tokens, items⟩
                simpa only [PortSchema.resultType,
                  ConcreteStructuralRealizer.realizePort] using
                  laws.bagCongruence embedding
                  (fun i => R.realizeOccurrence leftValues i)
                  (fun i => R.realizeOccurrence rightValues i) tokens
                  (fun i => by
                    simpa only [ConcreteStructuralRealizer.realizeOccurrence]
                      using elementIH (derivation := items i))
            | set =>
                simp only [ConcretePortAlignment] at derivation
                rcases derivation with
                  ⟨forwardMate, backwardMate, forward, backward⟩
                simpa only [PortSchema.resultType,
                  ConcreteStructuralRealizer.realizePort] using
                  laws.setCongruence embedding
                  (fun i => R.realizeOccurrence leftValues i)
                  (fun i => R.realizeOccurrence rightValues i)
                  forwardMate backwardMate
                  (fun i => by
                    simpa only [ConcreteStructuralRealizer.realizeOccurrence]
                      using elementIH (derivation := forward i))
                  (fun j => by
                    simpa only [ConcreteStructuralRealizer.realizeOccurrence]
                      using elementIH (derivation := backward j))
    | bind boundType body bodyIH =>
        cases left with
        | bind leftBody =>
          cases right with
          | bind rightBody =>
            unfold ConcretePortAlignment at derivation
            rcases derivation with ⟨innerScope, extension, bodyAlignment⟩
            simpa only [PortSchema.resultType,
              ConcreteStructuralRealizer.realizePort] using
              laws.binderCongruence embedding boundType scope innerScope
                extension (bodyIH (derivation := bodyAlignment))
    | bindBlock descriptor body bodyIH =>
        cases left with
        | bindBlock leftBody =>
          cases right with
          | bindBlock rightBody =>
            unfold ConcretePortAlignment at derivation
            rcases derivation with ⟨innerScope, extension, bodyAlignment⟩
            simpa only [PortSchema.resultType,
              ConcreteStructuralRealizer.realizePort] using
              laws.binderBlockCongruence embedding descriptor scope innerScope
                extension (bodyIH (derivation := bodyAlignment))

  /-- Certificate soundness for heterogeneous argument tuples. -/
  theorem argumentsCertificateSoundness
      {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
      {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
        Ty Descriptor ClassId Op}
      {L : TypedTermLanguage.{u, v, z} Ty}
      {R : ConcreteStructuralRealizer signature L}
      {policy : DescriptorAutomorphismPolicy signature}
      {AtomStep : {source target : TypedSlotContext.{u, v} Ty} ->
        (embedding : TypedSlotEmbedding source target) ->
        {bound : List Ty} -> (scope : TypedBoundPermutation bound) ->
        {output : Ty} -> ScopedPortAtom signature source bound output ->
          ScopedPortAtom signature target bound output -> Prop}
      (laws : ConcreteStructuralLaws R policy AtomStep)
      {source target : TypedSlotContext.{u, v} Ty}
      {embedding : TypedSlotEmbedding source target}
      {bound : List Ty} {scope : TypedBoundPermutation bound}
      {schemas : List (PortSchema Ty Descriptor)}
      {left : ConcreteArguments signature source bound schemas}
      {right : ConcreteArguments signature target bound schemas}
      (derivation : ConcreteArgumentsAlignment policy AtomStep embedding scope left right) :
      ConcreteArgumentCertificates L embedding
        (R.realizeArguments left) (R.realizeArguments right) := by
    induction schemas with
    | nil =>
        cases left
        cases right
        exact .nil
    | cons schema schemas tailIH =>
        cases left with
        | cons leftHead leftTail =>
          cases right with
          | cons rightHead rightTail =>
            simp only [ConcreteArgumentsAlignment] at derivation
            exact .cons
              (certificateSoundness laws derivation.1)
              (tailIH (derivation := derivation.2))

end ConcretePortAlignment

/-- Certificate soundness for a concrete heterogeneous node. -/
theorem concreteNodeAlignmentCertificateSoundness
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    {R : ConcreteStructuralRealizer signature L}
    {policy : DescriptorAutomorphismPolicy signature}
    {AtomStep : {source target : TypedSlotContext.{u, v} Ty} ->
      (embedding : TypedSlotEmbedding source target) ->
      {bound : List Ty} -> (scope : TypedBoundPermutation bound) ->
      {output : Ty} -> ScopedPortAtom signature source bound output ->
        ScopedPortAtom signature target bound output -> Prop}
    (laws : ConcreteStructuralLaws R policy AtomStep)
    {source target : TypedSlotContext.{u, v} Ty}
    {embedding : TypedSlotEmbedding source target} {output : Ty}
    {left : ConcreteFlexibleArityENode signature source output}
    {right : ConcreteFlexibleArityENode signature target output}
    (derivation : ConcreteNodeAlignment policy AtomStep embedding left right) :
    TypedEquationalCertificate L
      (L.rename embedding (R.realizeNode left)) (R.realizeNode right) := by
  cases derivation with
  | make operator arguments =>
      exact laws.nodeCongruence _ _
        (ConcretePortAlignment.argumentsCertificateSoundness laws arguments)

/-- Certificate soundness of the F12/F13 reflexive, symmetric, transitive
closure.  The inverse and composite cases use only the language's renaming
laws and the certificates recursively obtained from the direct generators. -/
theorem concreteAlphaPortClosureCertificateSoundness
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    {R : ConcreteStructuralRealizer signature L}
    {policy : DescriptorAutomorphismPolicy signature}
    (laws : ConcreteStructuralLaws R policy ConcreteAlphaAtomStep)
    {source target : TypedSlotContext.{u, v} Ty}
    {alignment : TypedSlotRenaming source target}
    {schema : PortSchema Ty Descriptor}
    {left : ConcretePort.Value signature source schema}
    {right : ConcretePort.Value signature target schema}
    (derivation : ConcreteTypedAlphaPort policy alignment left right) :
    TypedEquationalCertificate L
      (L.rename alignment.toTypedSlotEmbedding (R.realizePort left))
      (R.realizePort right) := by
  induction derivation with
  | reflexive port =>
      exact TypedEquationalCertificate.rewriteLeft
        (L.renameId (R.realizePort port)) (.reflexive (R.realizePort port))
  | direct innerDerivation =>
      exact ConcretePortAlignment.certificateSoundness laws innerDerivation
  | @symmetric source target schema innerAlignment innerLeft innerRight
      innerDerivation innerIH =>
      have transported := TypedEquationalCertificate.transport
        innerAlignment.inverse (TypedEquationalCertificate.symmetric innerIH)
      have cancel :
          L.rename innerAlignment.inverse
              (L.rename innerAlignment.toTypedSlotEmbedding
                (R.realizePort innerLeft)) =
            R.realizePort innerLeft := by
        rw [L.renameComp, innerAlignment.leftInverse, L.renameId]
      exact TypedEquationalCertificate.rewriteRight transported cancel
  | @transitive source middle target schema firstRenaming secondRenaming
      innerLeft middlePort innerRight first second firstIH secondIH =>
      have transported := TypedEquationalCertificate.transport
        secondRenaming.toTypedSlotEmbedding firstIH
      have chained := TypedEquationalCertificate.transitive transported secondIH
      exact TypedEquationalCertificate.rewriteLeft
        (L.renameComp secondRenaming.toTypedSlotEmbedding
          firstRenaming.toTypedSlotEmbedding (R.realizePort innerLeft)).symm chained

/-- F20: semantic soundness of the concrete indexed alpha relation, including
sequence, occurrence-bijective bag, mutual-mate set, unary-binder, and
descriptor-automorphism cases. -/
theorem concreteTypedAlphaSemanticSoundness
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    {R : ConcreteStructuralRealizer signature L}
    {policy : DescriptorAutomorphismPolicy signature}
    (laws : ConcreteStructuralLaws R policy ConcreteAlphaAtomStep)
    (model : TypedModel L)
    {source target : TypedSlotContext.{u, v} Ty}
    {alignment : TypedSlotRenaming source target}
    {schema : PortSchema Ty Descriptor}
    {left : ConcretePort.Value signature source schema}
    {right : ConcretePort.Value signature target schema}
    (derivation : ConcreteTypedAlphaPort policy alignment left right) :
    forall environment : model.Environment target,
      model.evaluate
          (L.rename alignment.toTypedSlotEmbedding (R.realizePort left)) environment =
        model.evaluate (R.realizePort right) environment :=
  typedCertificateSemanticSoundness model
    (concreteAlphaPortClosureCertificateSoundness laws derivation)

/-- TSG-ATOM-028: a distinct paper-facing name for evaluation transport of
the concrete indexed alpha relation. -/
theorem paperAtom028AlphaEquivalenceEvaluationTransport
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    {R : ConcreteStructuralRealizer signature L}
    {policy : DescriptorAutomorphismPolicy signature}
    (laws : ConcreteStructuralLaws R policy ConcreteAlphaAtomStep)
    (model : TypedModel L)
    {source target : TypedSlotContext.{u, v} Ty}
    {alignment : TypedSlotRenaming source target}
    {schema : PortSchema Ty Descriptor}
    {left : ConcretePort.Value signature source schema}
    {right : ConcretePort.Value signature target schema}
    (derivation : ConcreteTypedAlphaPort policy alignment left right) :
    forall environment : model.Environment target,
      model.evaluate
          (L.rename alignment.toTypedSlotEmbedding (R.realizePort left)) environment =
        model.evaluate (R.realizePort right) environment :=
  concreteTypedAlphaSemanticSoundness laws model derivation

/-- Local graph-relative leaf evidence: precisely one checked equational
certificate for the two realized atoms, after the stated outer transport. -/
structure CertifiedConcreteLeaf
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (R : ConcreteStructuralRealizer signature L)
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {bound : List Ty} (_scope : TypedBoundPermutation bound)
    {output : Ty} (left : ScopedPortAtom signature source bound output)
    (right : ScopedPortAtom signature target bound output) : Prop where
  certificate : TypedEquationalCertificate L
    (L.rename embedding (R.atom left)) (R.atom right)

/-- Constructor laws become full structural laws when every local leaf carries
its own checked certificate. -/
def certifiedConcreteStructuralLaws
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    (R : ConcreteStructuralRealizer signature L)
    (policy : DescriptorAutomorphismPolicy signature)
    (laws : ConcreteConstructorLaws R policy) :
    ConcreteStructuralLaws R policy (CertifiedConcreteLeaf R) where
  toConcreteConstructorLaws := laws
  atomCertificate := by
    intro source target embedding bound scope output left right leaf
    exact leaf.certificate

/-- F22 certificate conclusion: heterogeneous port/node congruence follows
only from per-leaf certificates and licensed one-constructor rules. -/
theorem concretePortAndNodeCongruenceCertificate
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    {R : ConcreteStructuralRealizer signature L}
    {policy : DescriptorAutomorphismPolicy signature}
    (laws : ConcreteConstructorLaws R policy)
    {source target : TypedSlotContext.{u, v} Ty}
    {embedding : TypedSlotEmbedding source target} {output : Ty}
    {left : ConcreteFlexibleArityENode signature source output}
    {right : ConcreteFlexibleArityENode signature target output}
    (derivation : ConcreteNodeAlignment policy (CertifiedConcreteLeaf R)
      embedding left right) :
    TypedEquationalCertificate L
      (L.rename embedding (R.realizeNode left)) (R.realizeNode right) :=
  concreteNodeAlignmentCertificateSoundness
    (certifiedConcreteStructuralLaws R policy laws) derivation

/-- TSG-ATOM-030: the exact direct-node equation receives its own declaration
instead of sharing F22's correspondence target. -/
theorem paperAtom030CertifiedGraphRelativeNodeEquation
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    {R : ConcreteStructuralRealizer signature L}
    {policy : DescriptorAutomorphismPolicy signature}
    (laws : ConcreteConstructorLaws R policy)
    {source target : TypedSlotContext.{u, v} Ty}
    {embedding : TypedSlotEmbedding source target} {output : Ty}
    {left : ConcreteFlexibleArityENode signature source output}
    {right : ConcreteFlexibleArityENode signature target output}
    (derivation : ConcreteNodeAlignment policy (CertifiedConcreteLeaf R)
      embedding left right) :
    TypedEquationalCertificate L
      (L.rename embedding (R.realizeNode left)) (R.realizeNode right) :=
  concretePortAndNodeCongruenceCertificate laws derivation

/-- F22 semantic consequence for every model of the licensed local theory. -/
theorem concretePortAndNodeCongruenceSemanticSoundness
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {L : TypedTermLanguage.{u, v, z} Ty}
    {R : ConcreteStructuralRealizer signature L}
    {policy : DescriptorAutomorphismPolicy signature}
    (laws : ConcreteConstructorLaws R policy) (model : TypedModel L)
    {source target : TypedSlotContext.{u, v} Ty}
    {embedding : TypedSlotEmbedding source target} {output : Ty}
    {left : ConcreteFlexibleArityENode signature source output}
    {right : ConcreteFlexibleArityENode signature target output}
    (derivation : ConcreteNodeAlignment policy (CertifiedConcreteLeaf R)
      embedding left right) :
    forall environment : model.Environment target,
      model.evaluate (L.rename embedding (R.realizeNode left)) environment =
        model.evaluate (R.realizeNode right) environment :=
  typedCertificateSemanticSoundness model
    (concretePortAndNodeCongruenceCertificate laws derivation)

end TypedSlottedEGraphsPaper
