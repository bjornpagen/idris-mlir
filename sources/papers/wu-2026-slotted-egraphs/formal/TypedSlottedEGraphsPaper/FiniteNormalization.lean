import Std

namespace TypedSlottedEGraphsPaper

namespace FiniteNormalization

universe u v

/-- Return the first member of `xs` related to `x`.  The relation is an input
and is not induced by the returned representative. -/
def firstRelated {α : Type u} (R : α → α → Prop) [DecidableRel R]
    (x : α) : List α → Option α
  | [] => none
  | y :: ys => if R x y then some y else firstRelated R x ys

theorem firstRelated_sound {α : Type u} {R : α → α → Prop}
    [DecidableRel R] {x y : α} {xs : List α}
    (h : firstRelated R x xs = some y) : y ∈ xs ∧ R x y := by
  induction xs with
  | nil =>
      simp [firstRelated] at h
  | cons z zs ih =>
      by_cases hxz : R x z
      · simp [firstRelated, hxz] at h
        cases h
        exact ⟨by simp, hxz⟩
      · simp [firstRelated, hxz] at h
        have hz := ih h
        exact ⟨by simp [hz.1], hz.2⟩

theorem firstRelated_complete {α : Type u} {R : α → α → Prop}
    [DecidableRel R] {x : α} {xs : List α}
    (h : ∃ y, y ∈ xs ∧ R x y) : ∃ y, firstRelated R x xs = some y := by
  induction xs with
  | nil =>
      simp at h
  | cons z zs ih =>
      by_cases hxz : R x z
      · exact ⟨z, by simp [firstRelated, hxz]⟩
      · have htail : ∃ y, y ∈ zs ∧ R x y := by
          rcases h with ⟨y, hy, hxy⟩
          simp only [List.mem_cons] at hy
          rcases hy with rfl | hy
          · exact False.elim (hxz hxy)
          · exact ⟨y, hy, hxy⟩
        rcases ih htail with ⟨y, hy⟩
        exact ⟨y, by simp [firstRelated, hxz, hy]⟩

theorem firstRelated_congr {α : Type u} {R : α → α → Prop}
    [DecidableRel R] {x y : α} {xs : List α}
    (h : ∀ z, z ∈ xs → (R x z ↔ R y z)) :
    firstRelated R x xs = firstRelated R y xs := by
  induction xs with
  | nil => rfl
  | cons z zs ih =>
      have hhead := h z (by simp)
      by_cases hxz : R x z
      · have hyz : R y z := hhead.mp hxz
        simp [firstRelated, hxz, hyz]
      · have hyz : ¬ R y z := by
          intro hyz
          exact hxz (hhead.mpr hyz)
        have htail : ∀ w, w ∈ zs → (R x w ↔ R y w) := by
          intro w hw
          exact h w (by simp [hw])
        simp [firstRelated, hxz, hyz, ih htail]

/-- Data sufficient to normalize a decidable equivalence relation whose
individual equivalence classes are explicitly and finitely enumerated.
`Std.LinearOrderPackage α` supplies the total comparison used to put each
orbit in a deterministic order before selection.  The ambient carrier need
not be finite. -/
structure Presentation (α : Type u) [Std.LinearOrderPackage α] where
  relation : α → α → Prop
  relationDecidable : DecidableRel relation
  orbit : α → List α
  orbitSelf : ∀ x, x ∈ orbit x
  orbitComplete : ∀ {x y}, relation x y → y ∈ orbit x
  orbitInvariant : ∀ {x y}, relation x y → orbit x = orbit y
  relationRefl : ∀ x, relation x x
  relationSymm : ∀ {x y}, relation x y → relation y x
  relationTrans : ∀ {x y z}, relation x y → relation y z → relation x z

namespace Presentation

variable {α : Type u} [Std.LinearOrderPackage α]

/-- The finite orbit of `x`, ordered by the supplied total order. -/
def orderedOrbit (P : Presentation α) (x : α) : List α :=
  (P.orbit x).mergeSort (fun y z => decide (y ≤ z))

theorem mem_orderedOrbit (P : Presentation α) (x y : α) :
    y ∈ P.orderedOrbit x ↔ y ∈ P.orbit x := by
  exact List.mem_mergeSort

theorem self_mem_orderedOrbit (P : Presentation α) (x : α) :
    x ∈ P.orderedOrbit x := by
  exact (P.mem_orderedOrbit x x).2 (P.orbitSelf x)

theorem orderedOrbit_invariant (P : Presentation α) {x y : α}
    (hxy : P.relation x y) : P.orderedOrbit x = P.orderedOrbit y := by
  simp only [orderedOrbit, P.orbitInvariant hxy]

/-- Choose the first related element in the order-normalized enumeration.
The fallback is unreachable because the enumeration is complete and the
relation is reflexive. -/
def normal (P : Presentation α) (x : α) : α :=
  letI : DecidableRel P.relation := P.relationDecidable
  (firstRelated P.relation x (P.orderedOrbit x)).getD x

theorem firstRelated_exists (P : Presentation α) (x : α) :
    letI : DecidableRel P.relation := P.relationDecidable
    ∃ y, firstRelated P.relation x (P.orderedOrbit x) = some y := by
  letI : DecidableRel P.relation := P.relationDecidable
  apply firstRelated_complete
  exact ⟨x, P.self_mem_orderedOrbit x, P.relationRefl x⟩

/-- The selected representative lies in the explicit finite orbit and is
related to the input. -/
theorem normal_mem_and_sound (P : Presentation α) (x : α) :
    P.normal x ∈ P.orbit x ∧ P.relation x (P.normal x) := by
  letI : DecidableRel P.relation := P.relationDecidable
  rcases P.firstRelated_exists x with ⟨y, hy⟩
  have hselected := firstRelated_sound hy
  have hnormal : P.normal x = y := by
    simp [normal, hy]
  rw [hnormal]
  exact ⟨(P.mem_orderedOrbit x y).1 hselected.1, hselected.2⟩

/-- Normalization is sound for the independently supplied relation. -/
theorem normal_sound (P : Presentation α) (x : α) :
    P.relation x (P.normal x) :=
  (P.normal_mem_and_sound x).2

theorem relation_iff_same_search (P : Presentation α) {x y : α}
    (hxy : P.relation x y) :
    letI : DecidableRel P.relation := P.relationDecidable
    firstRelated P.relation x (P.orderedOrbit x) =
      firstRelated P.relation y (P.orderedOrbit y) := by
  letI : DecidableRel P.relation := P.relationDecidable
  rw [P.orderedOrbit_invariant hxy]
  apply firstRelated_congr
  intro z _
  constructor
  · intro hxz
    exact P.relationTrans (P.relationSymm hxy) hxz
  · intro hyz
    exact P.relationTrans hxy hyz

/-- Exactness is derived: equal canonical representatives characterize the
original equivalence relation. -/
theorem normal_eq_normal_iff (P : Presentation α) (x y : α) :
    P.normal x = P.normal y ↔ P.relation x y := by
  constructor
  · intro hnormal
    have hleft : P.relation x (P.normal x) := P.normal_sound x
    have hright : P.relation (P.normal y) y :=
      P.relationSymm (P.normal_sound y)
    rw [hnormal] at hleft
    exact P.relationTrans hleft hright
  · intro hxy
    letI : DecidableRel P.relation := P.relationDecidable
    rcases P.firstRelated_exists x with ⟨z, hxz⟩
    have hsearch := P.relation_iff_same_search hxy
    have hyz : firstRelated P.relation y (P.orderedOrbit y) = some z :=
      hsearch.symm.trans hxz
    simp [normal, hxz, hyz]

/-- Canonicalization is idempotent. -/
theorem normal_idempotent (P : Presentation α) (x : α) :
    P.normal (P.normal x) = P.normal x := by
  apply (P.normal_eq_normal_iff (P.normal x) x).2
  exact P.relationSymm (P.normal_sound x)

end Presentation

/-- An effective shape map together with an independently specified kernel
equivalence on shapes.  No equality-via-normalization law is stored here. -/
structure EffectiveShapeWrapper (Node : Type u) (Shape : Type v)
    [Std.LinearOrderPackage Shape] where
  effectiveShape : Node → Shape
  kernel : Shape → Shape → Prop
  kernelDecidable : DecidableRel kernel
  orbit : Shape → List Shape
  orbitSelf : ∀ s, s ∈ orbit s
  orbitComplete : ∀ {s t}, kernel s t → t ∈ orbit s
  orbitInvariant : ∀ {s t}, kernel s t → orbit s = orbit t
  kernelRefl : ∀ s, kernel s s
  kernelSymm : ∀ {s t}, kernel s t → kernel t s
  kernelTrans : ∀ {r s t}, kernel r s → kernel s t → kernel r t

namespace EffectiveShapeWrapper

variable {Node : Type u} {Shape : Type v} [Std.LinearOrderPackage Shape]

def presentation (W : EffectiveShapeWrapper Node Shape) : Presentation Shape where
  relation := W.kernel
  relationDecidable := W.kernelDecidable
  orbit := W.orbit
  orbitSelf := W.orbitSelf
  orbitComplete := W.orbitComplete
  orbitInvariant := W.orbitInvariant
  relationRefl := W.kernelRefl
  relationSymm := W.kernelSymm
  relationTrans := W.kernelTrans

/-- The canonical effective shape of a node. -/
def canonicalShape (W : EffectiveShapeWrapper Node Shape) (n : Node) : Shape :=
  W.presentation.normal (W.effectiveShape n)

/-- Node-level shape equivalence delegates to the independent shape kernel. -/
def ShapeEquivalent (W : EffectiveShapeWrapper Node Shape) (x y : Node) : Prop :=
  W.kernel (W.effectiveShape x) (W.effectiveShape y)

theorem canonicalShape_sound (W : EffectiveShapeWrapper Node Shape) (n : Node) :
    W.kernel (W.effectiveShape n) (W.canonicalShape n) :=
  W.presentation.normal_sound (W.effectiveShape n)

/-- Effective-shape exactness follows from finite normalization; it is not an
assumption of the wrapper. -/
theorem canonicalShape_eq_iff (W : EffectiveShapeWrapper Node Shape)
    (x y : Node) :
    W.canonicalShape x = W.canonicalShape y ↔ W.ShapeEquivalent x y := by
  exact W.presentation.normal_eq_normal_iff (W.effectiveShape x) (W.effectiveShape y)

theorem canonicalShape_idempotent_on_shapes
    (W : EffectiveShapeWrapper Node Shape) (n : Node) :
    W.presentation.normal (W.canonicalShape n) = W.canonicalShape n := by
  exact W.presentation.normal_idempotent (W.effectiveShape n)

end EffectiveShapeWrapper

end FiniteNormalization

end TypedSlottedEGraphsPaper
