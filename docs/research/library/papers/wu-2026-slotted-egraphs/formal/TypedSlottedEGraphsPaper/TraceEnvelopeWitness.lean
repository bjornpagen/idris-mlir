import TypedSlottedEGraphsPaper.TraceSemantics
import TypedSlottedEGraphsPaper.ProfileRules

namespace TypedSlottedEGraphsPaper

/-!
  A concrete inhabitant of the trace envelope.  This is deliberately a
  witness, not a completeness theorem: it exercises one finite execution
  containing AC reassociation, an explicitly mapped binder block, a union,
  rebuild, and forward congruence restoration.
-/

namespace TraceEnvelopeWitness

structure BinderMapping where
  map : Bool → Bool
  inverse : Bool → Bool
  leftInverse : ∀ i, inverse (map i) = i
  rightInverse : ∀ i, map (inverse i) = i

def identityMapping : BinderMapping where
  map := id
  inverse := id
  leftInverse := by intro i; rfl
  rightInverse := by intro i; rfl

def swapMapping : BinderMapping where
  map := (!·)
  inverse := (!·)
  leftInverse := by intro i; cases i <;> rfl
  rightInverse := by intro i; cases i <;> rfl

inductive Node where
  | atom (value : Nat)
  | bound (slot : Bool)
  | ac (left right : Node)
  | bindBlock (mapping : BinderMapping) (body : Node)
  | union (left right : Node)
  | rebuilt (body : Node)

def meaning : Node → (Bool → Nat) → Nat → Prop
  | .atom value, _ => fun candidate => candidate = value
  | .bound slot, environment => fun candidate => candidate = environment slot
  | .ac left right, environment =>
      fun candidate => meaning left environment candidate ∨
        meaning right environment candidate
  | .bindBlock mapping body, environment =>
      meaning body (fun slot => environment (mapping.map slot))
  | .union left right, environment =>
      fun candidate => meaning left environment candidate ∨
        meaning right environment candidate
  | .rebuilt body, environment => meaning body environment

inductive Label where
  | acReassociate
  | binderRemap
  | unionInsert
  | rebuild
  | congruenceRestore

def binderBody : Node := .ac (.bound false) (.bound true)
def mappedIdentityBody : Node := .bindBlock identityMapping binderBody
def mappedSwapBody : Node := .bindBlock swapMapping binderBody
def acRightIdentity : Node :=
  .ac (.atom 1) (.ac (.atom 2) (.ac mappedIdentityBody (.atom 4)))
def acRightSwap : Node :=
  .ac (.atom 1) (.ac (.atom 2) (.ac mappedSwapBody (.atom 4)))
def unionTarget : Node := .union acRightSwap (.atom 4)
def rebuiltTarget : Node := .rebuilt unionTarget

def leftNode : Label → Node
  | .acReassociate =>
      .ac
        (.ac (.atom 1) (.atom 2))
        (.ac mappedIdentityBody (.atom 4))
  | .binderRemap => acRightIdentity
  | .unionInsert => acRightSwap
  | .rebuild => unionTarget
  | .congruenceRestore => rebuiltTarget

def rightNode : Label → Node
  | .acReassociate =>
      .ac (.atom 1)
        (.ac (.atom 2) (.ac mappedIdentityBody (.atom 4)))
  | .binderRemap => acRightSwap
  | .unionInsert => unionTarget
  | .rebuild => rebuiltTarget
  | .congruenceRestore => .rebuilt (.union (.atom 4) acRightSwap)

def envelopeSource : Node := leftNode .acReassociate

def envelopeTarget : Node := rightNode .congruenceRestore

def envelopeLabels : List Label :=
  [.acReassociate, .binderRemap, .unionInsert, .rebuild,
    .congruenceRestore]

def labelSource : Label → Node := leftNode
def labelTarget : Label → Node := rightNode

theorem acReassociateSound (environment : Bool → Nat) :
    meaning (leftNode .acReassociate) environment =
      meaning (rightNode .acReassociate) environment := by
  funext candidate
  simp [leftNode, rightNode, meaning, or_assoc]

theorem binderRemapSound (environment : Bool → Nat) :
    meaning (leftNode .binderRemap) environment =
      meaning (rightNode .binderRemap) environment := by
  funext candidate
  simp [leftNode, rightNode, acRightIdentity, acRightSwap,
    mappedIdentityBody, mappedSwapBody, binderBody, meaning,
    identityMapping, swapMapping, or_comm, or_left_comm, or_assoc]

theorem unionInsertSound (environment : Bool → Nat) :
    meaning (leftNode .unionInsert) environment =
      meaning (rightNode .unionInsert) environment := by
  funext candidate
  simp [leftNode, rightNode, acRightSwap, unionTarget, mappedSwapBody,
    binderBody, meaning, or_comm, or_left_comm, or_assoc]

theorem rebuildSound (environment : Bool → Nat) :
    meaning (leftNode .rebuild) environment =
      meaning (rightNode .rebuild) environment := by
  funext candidate
  simp [leftNode, rightNode, unionTarget, rebuiltTarget, acRightSwap,
    mappedSwapBody, binderBody, meaning]

theorem congruenceRestoreSound (environment : Bool → Nat) :
    meaning (leftNode .congruenceRestore) environment =
      meaning (rightNode .congruenceRestore) environment := by
  funext candidate
  simp [leftNode, rightNode, rebuiltTarget, unionTarget, acRightSwap,
    mappedSwapBody, binderBody, meaning, or_comm, or_left_comm, or_assoc]

def interpreter : ProfileRules.TraceInterpreter Label labelSource labelTarget
    ((Bool → Nat) → Nat → Prop) where
  denote node := meaning node
  localCertificate label := by
    cases label with
    | acReassociate => exact funext acReassociateSound
    | binderRemap => exact funext binderRemapSound
    | unionInsert => exact funext unionInsertSound
    | rebuild => exact funext rebuildSound
    | congruenceRestore => exact funext congruenceRestoreSound

def trace : ProfileRules.StructuralTrace Label labelSource labelTarget
    envelopeSource envelopeTarget := by
  exact .cons Label.acReassociate
    (.cons Label.binderRemap
      (.cons Label.unionInsert
        (.cons Label.rebuild
          (.cons Label.congruenceRestore (.nil _)))))

/- D1: exact adjacency and the requested event order are enforced by the
   indexed trace constructor, not by a Boolean side condition. -/
theorem d1_trace_obligation :
    Nonempty (ProfileRules.StructuralTrace Label labelSource labelTarget
      envelopeSource envelopeTarget) := ⟨trace⟩

/- D2: replay of every local certificate reaches the final node. -/
theorem d2_trace_obligation :
    interpreter.denote envelopeSource = interpreter.denote envelopeTarget :=
  ProfileRules.replayTrace interpreter trace

theorem machineCheckedEndToEndWitness :
    (∃ t : ProfileRules.StructuralTrace Label labelSource labelTarget
        envelopeSource envelopeTarget, True) ∧
      interpreter.denote envelopeSource = interpreter.denote envelopeTarget := by
  exact ⟨⟨trace, True.intro⟩, d2_trace_obligation⟩

end TraceEnvelopeWitness
end TypedSlottedEGraphsPaper
