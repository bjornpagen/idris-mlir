import TypedSlottedEGraphsPaper.Core

namespace TypedSlottedEGraphsPaper

universe u v w x y

/-- The concrete signature data needed by the intrinsically typed syntax.
    Bound variables are represented by a typed de Bruijn context.  This makes
    freshness canonical and keeps them disjoint from the free slot context. -/
structure ConcreteSyntaxSignature
    (Ty : Type u) (Descriptor : Type x) (ClassId : Type w) (Op : Type y) where
  classInterface : ClassId → TypedSlotContext.{u, v} Ty
  classOutput : ClassId → Ty
  boundTypes : Descriptor → List Ty
  inputSchemas : Op → List (PortSchema Ty Descriptor)
  outputType : Op → Ty

/-- A one-valued port atom.  Free slots carry a checked type equation, local
    variables are indexed into a typed de Bruijn context, and invocations carry
    a typed embedding from the callee interface. -/
inductive ScopedPortAtom {Ty : Type u} {Descriptor : Type x}
    {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    (context : TypedSlotContext.{u, v} Ty) (bound : List Ty) : Ty → Type _ where
  | free {output : Ty} (slot : context.Slot)
      (wellTyped : context.typeOf slot = output) :
      ScopedPortAtom signature context bound output
  | boundVar {output : Ty} (index : Fin bound.length)
      (wellTyped : bound.get index = output) :
      ScopedPortAtom signature context bound output
  | invoke (classId : ClassId)
      (embedding : TypedSlotEmbedding (signature.classInterface classId) context) :
      ScopedPortAtom signature context bound (signature.classOutput classId)

namespace ScopedPortAtom

/-- Concrete action of a typed embedding on atoms.  Local indices are fixed;
    invocation embeddings compose on the left. -/
def act {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty} {bound : List Ty}
    (embedding : TypedSlotEmbedding source target) {output : Ty} :
    ScopedPortAtom signature source bound output →
      ScopedPortAtom signature target bound output
  | .free slot wellTyped =>
      .free (embedding.toFun slot)
        ((embedding.preservesType slot).trans wellTyped)
  | .boundVar index wellTyped => .boundVar index wellTyped
  | .invoke classId inner =>
      .invoke classId (TypedSlotEmbedding.comp embedding inner)

/-- Free-slot support of an atom.  A local variable has no free support and an
    invocation supports exactly the image of its interface embedding. -/
def Supports {Ty : Type u} {Descriptor : Type x} {ClassId : Type w}
    {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {context : TypedSlotContext.{u, v} Ty} {bound : List Ty} {output : Ty} :
    ScopedPortAtom signature context bound output → context.Slot → Prop
  | .free slot _, candidate => slot = candidate
  | .boundVar _ _, _ => False
  | .invoke _ embedding, candidate =>
      ∃ interfaceSlot, embedding.toFun interfaceSlot = candidate

/-- The support of the concrete atom action is exactly the direct image of
    the original support. -/
theorem supports_act_exact {Ty : Type u} {Descriptor : Type x}
    {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty} {bound : List Ty}
    (embedding : TypedSlotEmbedding source target) {output : Ty}
    (atom : ScopedPortAtom signature source bound output)
    (candidate : target.Slot) :
    Supports (act embedding atom) candidate ↔
      ∃ sourceSlot, Supports atom sourceSlot ∧
        embedding.toFun sourceSlot = candidate := by
  cases atom with
  | free slot wellTyped =>
      constructor
      · intro h
        exact ⟨slot, rfl, h⟩
      · rintro ⟨sourceSlot, hs, himage⟩
        cases hs
        exact himage
  | boundVar index wellTyped =>
      constructor
      · intro h
        contradiction
      · rintro ⟨sourceSlot, hs, himage⟩
        contradiction
  | invoke classId inner =>
      constructor
      · rintro ⟨interfaceSlot, himage⟩
        exact ⟨inner.toFun interfaceSlot, ⟨interfaceSlot, rfl⟩, himage⟩
      · rintro ⟨sourceSlot, ⟨interfaceSlot, hinner⟩, houter⟩
        refine ⟨interfaceSlot, ?_⟩
        exact (congrArg embedding.toFun hinner).trans houter

end ScopedPortAtom

/- Concrete port values and homogeneous container payloads.  The latter are
   length-indexed, so an arity license is checked at construction time. -/
mutual
  inductive ConcretePort {Ty : Type u} {Descriptor : Type x}
      {ClassId : Type w} {Op : Type y}
      (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
        Ty Descriptor ClassId Op)
      (context : TypedSlotContext.{u, v} Ty) :
      List Ty → PortSchema Ty Descriptor → Type _ where
    | atom {output : Ty}
        (value : ScopedPortAtom signature context bound output) :
        ConcretePort signature context bound (.one output)
    | container {kind : ContainerKind} {arity : ArityLicense}
        {element : PortSchema Ty Descriptor} {size : Nat}
        (values : ConcretePorts signature context bound element size)
        (licensed : arity.admits size) :
        ConcretePort signature context bound (.container kind arity element)
    | bind {boundType : Ty} {body : PortSchema Ty Descriptor}
        (value : ConcretePort signature context (boundType :: bound) body) :
        ConcretePort signature context bound (.bind boundType body)
    | bindBlock {descriptor : Descriptor} {body : PortSchema Ty Descriptor}
        (value : ConcretePort signature context
          (signature.boundTypes descriptor ++ bound) body) :
        ConcretePort signature context bound (.bindBlock descriptor body)

  inductive ConcretePorts {Ty : Type u} {Descriptor : Type x}
      {ClassId : Type w} {Op : Type y}
      (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
        Ty Descriptor ClassId Op)
      (context : TypedSlotContext.{u, v} Ty) :
      List Ty → PortSchema Ty Descriptor → Nat → Type _ where
    | nil {schema : PortSchema Ty Descriptor} :
        ConcretePorts signature context bound schema 0
    | cons {schema : PortSchema Ty Descriptor} {size : Nat}
        (head : ConcretePort signature context bound schema)
        (tail : ConcretePorts signature context bound schema size) :
        ConcretePorts signature context bound schema (size + 1)
end

namespace ConcretePort

/-- A top-level port has no local variables outside its own binders. -/
abbrev Value {Ty : Type u} {Descriptor : Type x} {ClassId : Type w}
    {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    (context : TypedSlotContext.{u, v} Ty)
    (schema : PortSchema Ty Descriptor) :=
  ConcretePort signature context [] schema

mutual
  /-- Embedding action on a port, structurally recursive through containers
      and binders. -/
  def act {Ty : Type u} {Descriptor : Type x} {ClassId : Type w}
      {Op : Type y}
      {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
        Ty Descriptor ClassId Op}
      {source target : TypedSlotContext.{u, v} Ty} {bound : List Ty}
      (embedding : TypedSlotEmbedding source target) :
      {schema : PortSchema Ty Descriptor} →
      ConcretePort signature source bound schema →
        ConcretePort signature target bound schema
    | _, .atom value => .atom (ScopedPortAtom.act embedding value)
    | _, .container values licensed =>
        .container (ConcretePorts.act embedding values) licensed
    | _, .bind value => .bind (act embedding value)
    | _, .bindBlock value => .bindBlock (act embedding value)

  /-- Componentwise embedding action on a homogeneous container payload. -/
  def ConcretePorts.act {Ty : Type u} {Descriptor : Type x}
      {ClassId : Type w} {Op : Type y}
      {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
        Ty Descriptor ClassId Op}
      {source target : TypedSlotContext.{u, v} Ty} {bound : List Ty}
      (embedding : TypedSlotEmbedding source target) :
      {schema : PortSchema Ty Descriptor} → {size : Nat} →
      ConcretePorts signature source bound schema size →
        ConcretePorts signature target bound schema size
    | _, _, .nil => .nil
    | _, _, .cons head tail =>
        .cons (act embedding head) (ConcretePorts.act embedding tail)
end

mutual
  /-- Free support of a port.  Binder-local indices are absent from this
      predicate by construction. -/
  def Supports {Ty : Type u} {Descriptor : Type x} {ClassId : Type w}
      {Op : Type y}
      {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
        Ty Descriptor ClassId Op}
      {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
      {schema : PortSchema Ty Descriptor} :
      ConcretePort signature context bound schema → context.Slot → Prop
    | .atom value, slot => ScopedPortAtom.Supports value slot
    | .container values _, slot => ConcretePorts.Supports values slot
    | .bind value, slot => Supports value slot
    | .bindBlock value, slot => Supports value slot

  /-- Union support of a homogeneous container payload. -/
  def ConcretePorts.Supports {Ty : Type u} {Descriptor : Type x}
      {ClassId : Type w} {Op : Type y}
      {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
        Ty Descriptor ClassId Op}
      {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
      {schema : PortSchema Ty Descriptor} {size : Nat} :
      ConcretePorts signature context bound schema size → context.Slot → Prop
    | .nil, _ => False
    | .cons head tail, slot => Supports head slot ∨ ConcretePorts.Supports tail slot
end

/-- Exact support-image theorem for concrete ports, including recursive
    containers and both binder forms. -/
theorem supports_act_exact {Ty : Type u} {Descriptor : Type x}
    {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty} {bound : List Ty}
    (embedding : TypedSlotEmbedding source target)
    {schema : PortSchema Ty Descriptor}
    (port : ConcretePort signature source bound schema)
    (candidate : target.Slot) :
    Supports (act embedding port) candidate ↔
      ∃ sourceSlot, Supports port sourceSlot ∧
        embedding.toFun sourceSlot = candidate := by
  refine ConcretePort.rec
    (motive_1 := fun _ _ value => ∀ candidate,
      Supports (act embedding value) candidate ↔
        ∃ sourceSlot, Supports value sourceSlot ∧
          embedding.toFun sourceSlot = candidate)
    (motive_2 := fun _ _ _ values => ∀ candidate,
      ConcretePorts.Supports (ConcretePorts.act embedding values) candidate ↔
        ∃ sourceSlot, ConcretePorts.Supports values sourceSlot ∧
          embedding.toFun sourceSlot = candidate)
    ?_ ?_ ?_ ?_ ?_ ?_ port candidate
  · intro bound output value candidate
    exact ScopedPortAtom.supports_act_exact embedding value candidate
  · intro bound kind arity element size values licensed valuesIH candidate
    exact valuesIH candidate
  · intro bound boundType body value valueIH candidate
    exact valueIH candidate
  · intro bound descriptor body value valueIH candidate
    exact valueIH candidate
  · intro bound schema candidate
    constructor
    · intro h
      contradiction
    · rintro ⟨sourceSlot, hs, himage⟩
      contradiction
  · intro bound schema size head tail headIH tailIH candidate
    constructor
    · intro h
      cases h with
      | inl hhead =>
          rcases (headIH candidate).mp hhead with
            ⟨sourceSlot, hs, himage⟩
          exact ⟨sourceSlot, Or.inl hs, himage⟩
      | inr htail =>
          rcases (tailIH candidate).mp htail with
            ⟨sourceSlot, hs, himage⟩
          exact ⟨sourceSlot, Or.inr hs, himage⟩
    · rintro ⟨sourceSlot, hs, himage⟩
      cases hs with
      | inl hhead =>
          exact Or.inl ((headIH candidate).mpr
            ⟨sourceSlot, hhead, himage⟩)
      | inr htail =>
          exact Or.inr ((tailIH candidate).mpr
            ⟨sourceSlot, htail, himage⟩)

/-- Exact support-image theorem for concrete homogeneous containers. -/
theorem ConcretePorts.supports_act_exact {Ty : Type u}
    {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty} {bound : List Ty}
    (embedding : TypedSlotEmbedding source target)
    {schema : PortSchema Ty Descriptor} {size : Nat}
    (ports : ConcretePorts signature source bound schema size)
    (candidate : target.Slot) :
    ConcretePorts.Supports (ConcretePorts.act embedding ports) candidate ↔
      ∃ sourceSlot, ConcretePorts.Supports ports sourceSlot ∧
        embedding.toFun sourceSlot = candidate := by
  refine ConcretePorts.rec
    (motive_1 := fun _ _ value => ∀ candidate,
      ConcretePort.Supports (ConcretePort.act embedding value) candidate ↔
        ∃ sourceSlot, ConcretePort.Supports value sourceSlot ∧
          embedding.toFun sourceSlot = candidate)
    (motive_2 := fun _ _ _ values => ∀ candidate,
      ConcretePorts.Supports (ConcretePorts.act embedding values) candidate ↔
        ∃ sourceSlot, ConcretePorts.Supports values sourceSlot ∧
          embedding.toFun sourceSlot = candidate)
    ?_ ?_ ?_ ?_ ?_ ?_ ports candidate
  · intro bound output value candidate
    exact ScopedPortAtom.supports_act_exact embedding value candidate
  · intro bound kind arity element size values licensed valuesIH candidate
    exact valuesIH candidate
  · intro bound boundType body value valueIH candidate
    exact valueIH candidate
  · intro bound descriptor body value valueIH candidate
    exact valueIH candidate
  · intro bound schema candidate
    constructor
    · intro h
      contradiction
    · rintro ⟨sourceSlot, hs, himage⟩
      contradiction
  · intro bound schema size head tail headIH tailIH candidate
    constructor
    · intro h
      cases h with
      | inl hhead =>
          rcases (headIH candidate).mp hhead with
            ⟨sourceSlot, hs, himage⟩
          exact ⟨sourceSlot, Or.inl hs, himage⟩
      | inr htail =>
          rcases (tailIH candidate).mp htail with
            ⟨sourceSlot, hs, himage⟩
          exact ⟨sourceSlot, Or.inr hs, himage⟩
    · rintro ⟨sourceSlot, hs, himage⟩
      cases hs with
      | inl hhead =>
          exact Or.inl ((headIH candidate).mpr
            ⟨sourceSlot, hhead, himage⟩)
      | inr htail =>
          exact Or.inr ((tailIH candidate).mpr
            ⟨sourceSlot, htail, himage⟩)

end ConcretePort

/-- A signature-indexed tuple of ports. -/
inductive ConcreteArguments {Ty : Type u} {Descriptor : Type x}
    {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    (context : TypedSlotContext.{u, v} Ty) (bound : List Ty) :
    List (PortSchema Ty Descriptor) → Type _ where
  | nil : ConcreteArguments signature context bound []
  | cons {schema : PortSchema Ty Descriptor}
      {schemas : List (PortSchema Ty Descriptor)}
      (head : ConcretePort signature context bound schema)
      (tail : ConcreteArguments signature context bound schemas) :
      ConcreteArguments signature context bound (schema :: schemas)

namespace ConcreteArguments

def act {Ty : Type u} {Descriptor : Type x} {ClassId : Type w}
    {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty} {bound : List Ty}
    (embedding : TypedSlotEmbedding source target) :
    {schemas : List (PortSchema Ty Descriptor)} →
    ConcreteArguments signature source bound schemas →
      ConcreteArguments signature target bound schemas
  | _, .nil => .nil
  | _, .cons head tail =>
      .cons (ConcretePort.act embedding head) (act embedding tail)

def Supports {Ty : Type u} {Descriptor : Type x} {ClassId : Type w}
    {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {context : TypedSlotContext.{u, v} Ty} {bound : List Ty}
    {schemas : List (PortSchema Ty Descriptor)} :
    ConcreteArguments signature context bound schemas → context.Slot → Prop
  | .nil, _ => False
  | .cons head tail, slot =>
      ConcretePort.Supports head slot ∨ Supports tail slot

theorem supports_act_exact {Ty : Type u} {Descriptor : Type x}
    {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty} {bound : List Ty}
    (embedding : TypedSlotEmbedding source target)
    {schemas : List (PortSchema Ty Descriptor)}
    (arguments : ConcreteArguments signature source bound schemas)
    (candidate : target.Slot) :
    Supports (act embedding arguments) candidate ↔
      ∃ sourceSlot, Supports arguments sourceSlot ∧
        embedding.toFun sourceSlot = candidate := by
  induction arguments with
  | nil =>
      constructor
      · intro h
        contradiction
      · rintro ⟨sourceSlot, hs, himage⟩
        contradiction
  | cons head tail ih =>
      constructor
      · intro h
        cases h with
        | inl hhead =>
            rcases (ConcretePort.supports_act_exact embedding head candidate).mp hhead with
              ⟨sourceSlot, hs, himage⟩
            exact ⟨sourceSlot, Or.inl hs, himage⟩
        | inr htail =>
            rcases ih.mp htail with ⟨sourceSlot, hs, himage⟩
            exact ⟨sourceSlot, Or.inr hs, himage⟩
      · rintro ⟨sourceSlot, hs, himage⟩
        cases hs with
        | inl hhead =>
            exact Or.inl ((ConcretePort.supports_act_exact embedding head candidate).mpr
              ⟨sourceSlot, hhead, himage⟩)
        | inr htail =>
            exact Or.inr (ih.mpr ⟨sourceSlot, htail, himage⟩)

end ConcreteArguments

/-- A concrete intrinsically typed flexible-arity node.  Its output index and
    complete input schema are selected by its signature operation. -/
inductive ConcreteFlexibleArityENode {Ty : Type u} {Descriptor : Type x}
    {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    (context : TypedSlotContext.{u, v} Ty) : Ty → Type _ where
  | make (operator : Op)
      (arguments : ConcreteArguments signature context []
        (signature.inputSchemas operator)) :
      ConcreteFlexibleArityENode signature context (signature.outputType operator)

namespace ConcreteFlexibleArityENode

def act {Ty : Type u} {Descriptor : Type x} {ClassId : Type w}
    {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {output : Ty} :
    ConcreteFlexibleArityENode signature source output →
      ConcreteFlexibleArityENode signature target output
  | .make operator arguments =>
      .make operator (ConcreteArguments.act embedding arguments)

def output {Ty : Type u} {Descriptor : Type x} {ClassId : Type w}
    {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {context : TypedSlotContext.{u, v} Ty} {result : Ty}
    (_ : ConcreteFlexibleArityENode signature context result) : Ty := result

def Supports {Ty : Type u} {Descriptor : Type x} {ClassId : Type w}
    {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {context : TypedSlotContext.{u, v} Ty} {output : Ty} :
    ConcreteFlexibleArityENode signature context output → context.Slot → Prop
  | .make _ arguments, slot => ConcreteArguments.Supports arguments slot

theorem supports_act_exact {Ty : Type u} {Descriptor : Type x}
    {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target) {output : Ty}
    (node : ConcreteFlexibleArityENode signature source output)
    (candidate : target.Slot) :
    Supports (act embedding node) candidate ↔
      ∃ sourceSlot, Supports node sourceSlot ∧
        embedding.toFun sourceSlot = candidate := by
  cases node with
  | make operator arguments =>
      exact ConcreteArguments.supports_act_exact embedding arguments candidate

end ConcreteFlexibleArityENode

/-- F07: the concrete action exposes the exact acted terms at the same
    schema/output indices, and the node output is unchanged. -/
theorem concreteTypedEmbeddingsPreserveTypes
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {schema : PortSchema Ty Descriptor}
    (port : ConcretePort.Value signature source schema)
    {result : Ty} (node : ConcreteFlexibleArityENode signature source result) :
    (∃ actedPort : ConcretePort.Value signature target schema,
        actedPort = ConcretePort.act embedding port) ∧
      (∃ actedNode : ConcreteFlexibleArityENode signature target result,
        actedNode = ConcreteFlexibleArityENode.act embedding node) ∧
      ConcreteFlexibleArityENode.output
          (ConcreteFlexibleArityENode.act embedding node) =
        ConcreteFlexibleArityENode.output node := by
  exact ⟨⟨ConcretePort.act embedding port, rfl⟩,
    ⟨ConcreteFlexibleArityENode.act embedding node, rfl⟩, rfl⟩

/-- Direct image of a slot predicate under an embedding. -/
def slotSupportImage {Ty : Type u}
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    (support : source.Slot → Prop) : target.Slot → Prop :=
  fun candidate => ∃ sourceSlot, support sourceSlot ∧
    embedding.toFun sourceSlot = candidate

/-- Predicate equality version of exact support transport for ports. -/
theorem concretePortSupportImageEquality
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {schema : PortSchema Ty Descriptor}
    (port : ConcretePort.Value signature source schema) :
    ConcretePort.Supports (ConcretePort.act embedding port) =
      slotSupportImage embedding (ConcretePort.Supports port) := by
  funext candidate
  apply propext
  exact ConcretePort.supports_act_exact embedding port candidate

/-- Predicate equality version of exact support transport for nodes. -/
theorem concreteNodeSupportImageEquality
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {result : Ty} (node : ConcreteFlexibleArityENode signature source result) :
    ConcreteFlexibleArityENode.Supports
        (ConcreteFlexibleArityENode.act embedding node) =
      slotSupportImage embedding (ConcreteFlexibleArityENode.Supports node) := by
  funext candidate
  apply propext
  exact ConcreteFlexibleArityENode.supports_act_exact embedding node candidate

/-- F08: port and node support map exactly to their direct images under the
    embedding. -/
theorem concreteSlotSupportInvariance
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    {signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op}
    {source target : TypedSlotContext.{u, v} Ty}
    (embedding : TypedSlotEmbedding source target)
    {schema : PortSchema Ty Descriptor}
    (port : ConcretePort.Value signature source schema)
    {result : Ty} (node : ConcreteFlexibleArityENode signature source result) :
    ConcretePort.Supports (ConcretePort.act embedding port) =
        slotSupportImage embedding (ConcretePort.Supports port) ∧
      ConcreteFlexibleArityENode.Supports
          (ConcreteFlexibleArityENode.act embedding node) =
        slotSupportImage embedding
          (ConcreteFlexibleArityENode.Supports node) := by
  exact ⟨concretePortSupportImageEquality embedding port,
    concreteNodeSupportImageEquality embedding node⟩

/-- A concrete invocation-valued one-port. -/
def concreteInvocation {Ty : Type u} {Descriptor : Type x}
    {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    {context : TypedSlotContext.{u, v} Ty} (classId : ClassId)
    (embedding : TypedSlotEmbedding (signature.classInterface classId) context) :
    ConcretePort.Value signature context (.one (signature.classOutput classId)) :=
  .atom (.invoke classId embedding)

/-- The bare class occurrence is its identity-embedded invocation. -/
def concreteIdentityInvocation {Ty : Type u} {Descriptor : Type x}
    {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    (classId : ClassId) :
    ConcretePort.Value signature (signature.classInterface classId)
      (.one (signature.classOutput classId)) :=
  concreteInvocation signature classId
    (TypedSlotEmbedding.id (signature.classInterface classId))

/-- F09: invocation construction has the callee output type; identity is the
    bare occurrence; and every ambient action composes the invocation
    embedding.  Only the action law is quantified over the outer embedding. -/
theorem concreteTypeSafetyOfInvocation
    {Ty : Type u} {Descriptor : Type x} {ClassId : Type w} {Op : Type y}
    (signature : ConcreteSyntaxSignature.{u, v, w, x, y}
      Ty Descriptor ClassId Op)
    {context : TypedSlotContext.{u, v} Ty}
    (classId : ClassId)
    (inner : TypedSlotEmbedding (signature.classInterface classId) context) :
    (∃ invocation : ConcretePort.Value signature context
        (.one (signature.classOutput classId)),
      invocation = concreteInvocation signature classId inner) ∧
    concreteInvocation signature classId
        (TypedSlotEmbedding.id (signature.classInterface classId)) =
      concreteIdentityInvocation signature classId ∧
    ∀ {target : TypedSlotContext.{u, v} Ty}
      (outer : TypedSlotEmbedding context target),
      ConcretePort.act outer (concreteInvocation signature classId inner) =
        concreteInvocation signature classId
          (TypedSlotEmbedding.comp outer inner) := by
  exact ⟨⟨concreteInvocation signature classId inner, rfl⟩, rfl,
    fun outer => rfl⟩

end TypedSlottedEGraphsPaper
