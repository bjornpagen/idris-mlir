import Std

namespace TypedSlottedEGraphsPaper.ACClosureCounts

/-!
This module gives the finite combinatorial content of F01 without assuming a
coding at either advertised cardinality. Words are generated inductively and
their exact finite codings are assembled from the constructors. Closed-form
cardinalities are proved only after those recursive codings exist.
-/

/-- An explicit two-sided finite coding. -/
structure FiniteCoding (alpha : Type) (cardinality : Nat) where
  encode : alpha -> Fin cardinality
  decode : Fin cardinality -> alpha
  decode_encode : forall x, decode (encode x) = x
  encode_decode : forall i, encode (decode i) = i

/-- A local, universe-monomorphic type equivalence.  `Std` deliberately does
not supply Mathlib's `Equiv`, so the four inverse data are kept explicitly. -/
structure TypeEquiv (alpha beta : Type) where
  toFun : alpha -> beta
  invFun : beta -> alpha
  left_inv : forall x, invFun (toFun x) = x
  right_inv : forall y, toFun (invFun y) = y

namespace FiniteCoding

def empty : FiniteCoding Empty 0 where
  encode x := nomatch x
  decode i := Fin.elim0 i
  decode_encode x := nomatch x
  encode_decode i := Fin.elim0 i

def unit : FiniteCoding Unit 1 where
  encode _ := ⟨0, by omega⟩
  decode _ := ()
  decode_encode _ := rfl
  encode_decode i := by
    apply Fin.ext
    omega

def ofEquiv {alpha beta : Type} {n : Nat} (e : TypeEquiv alpha beta)
    (c : FiniteCoding beta n) : FiniteCoding alpha n where
  encode x := c.encode (e.toFun x)
  decode i := e.invFun (c.decode i)
  decode_encode x := by rw [c.decode_encode, e.left_inv]
  encode_decode i := by rw [e.right_inv, c.encode_decode]

def castCard {alpha : Type} {m n : Nat} (h : m = n)
    (c : FiniteCoding alpha m) : FiniteCoding alpha n := by
  cases h
  exact c

def sum {alpha beta : Type} {m n : Nat}
    (ca : FiniteCoding alpha m) (cb : FiniteCoding beta n) :
    FiniteCoding (Sum alpha beta) (m + n) where
  encode
    | .inl a => ⟨(ca.encode a).val, by omega⟩
    | .inr b => ⟨m + (cb.encode b).val, by omega⟩
  decode i :=
    if h : i.val < m then
      .inl (ca.decode ⟨i.val, h⟩)
    else
      .inr (cb.decode ⟨i.val - m, by omega⟩)
  decode_encode x := by
    cases x with
    | inl a =>
        simp only
        split
        · simp [ca.decode_encode]
        · rename_i h
          exact (h (ca.encode a).isLt).elim
    | inr b =>
        simp only
        split
        · rename_i h
          omega
        · simp [cb.decode_encode]
  encode_decode i := by
    by_cases h : i.val < m
    · simp only [dif_pos h]
      have hc : (ca.encode (ca.decode ⟨i.val, h⟩)).val = i.val :=
        congrArg (fun j : Fin m => j.val) (ca.encode_decode ⟨i.val, h⟩)
      apply Fin.ext
      exact hc
    · simp only [dif_neg h]
      apply Fin.ext
      have hc :
          (cb.encode (cb.decode ⟨i.val - m, by omega⟩)).val = i.val - m :=
        congrArg (fun j : Fin n => j.val)
          (cb.encode_decode ⟨i.val - m, by omega⟩)
      change m + (cb.encode (cb.decode ⟨i.val - m, by omega⟩)).val = i.val
      omega

end FiniteCoding

/-! ## Nonempty binary masks (free commutative-semigroup product classes) -/

/-- `BinaryMask n false` is the all-zero mask; `BinaryMask n true` is a mask
containing at least one generator. Thus nonemptiness is represented by the
index and cannot be forged by an unrelated proof field. -/
inductive BinaryMask : Nat -> Bool -> Type where
  | nil : BinaryMask 0 false
  | absent : BinaryMask n used -> BinaryMask (n + 1) used
  | present : BinaryMask n used -> BinaryMask (n + 1) true

/-- A free commutative-semigroup product class on `n` distinct generators is
exactly a nonempty binary support mask. There is no unit constructor. -/
abbrev ACProductClass (n : Nat) := BinaryMask n true

def BinaryMask.assignment : BinaryMask n used -> Fin n -> Bool
  | .nil, i => Fin.elim0 i
  | .absent tail, i => Fin.cases false tail.assignment i
  | .present tail, i => Fin.cases true tail.assignment i

def BinaryMask.witness : (mask : BinaryMask n true) -> Fin n
  | .absent tail => (tail.witness).succ
  | .present _ => 0

@[simp] theorem BinaryMask.assignment_witness
    (mask : BinaryMask n true) : mask.assignment mask.witness = true := by
  cases mask with
  | absent tail => exact BinaryMask.assignment_witness tail
  | present tail => rfl

/-- The recursively generated number of binary masks in each occupancy state. -/
def binaryMaskCount : Nat -> Bool -> Nat
  | 0, false => 1
  | 0, true => 0
  | n + 1, false => binaryMaskCount n false
  | n + 1, true =>
      binaryMaskCount n true +
        (binaryMaskCount n false + binaryMaskCount n true)

private def binaryFalseZeroEquiv : TypeEquiv (BinaryMask 0 false) Unit where
  toFun
    | .nil => ()
  invFun _ := .nil
  left_inv
    | .nil => rfl
  right_inv _ := rfl

private def binaryTrueZeroEquiv : TypeEquiv (BinaryMask 0 true) Empty where
  toFun x := nomatch x
  invFun x := nomatch x
  left_inv x := nomatch x
  right_inv x := nomatch x

private def binaryFalseSuccEquiv (n : Nat) :
    TypeEquiv (BinaryMask (n + 1) false) (BinaryMask n false) where
  toFun
    | .absent tail => tail
  invFun := .absent
  left_inv
    | .absent _tail => rfl
  right_inv _ := rfl

private def binaryTrueSuccEquiv (n : Nat) :
    TypeEquiv (BinaryMask (n + 1) true)
      (Sum (BinaryMask n true) (Sum (BinaryMask n false) (BinaryMask n true))) where
  toFun
    | .absent tail => .inl tail
    | .present (used := false) tail => .inr (.inl tail)
    | .present (used := true) tail => .inr (.inr tail)
  invFun
    | .inl tail => .absent tail
    | .inr (.inl tail) => .present tail
    | .inr (.inr tail) => .present tail
  left_inv
    | .absent _tail => rfl
    | .present (used := false) _tail => rfl
    | .present (used := true) _tail => rfl
  right_inv
    | .inl _tail => rfl
    | .inr (.inl _tail) => rfl
    | .inr (.inr _tail) => rfl

/-- A coding derived solely from the mask constructors. -/
def binaryMaskCoding : (n : Nat) -> (used : Bool) ->
    FiniteCoding (BinaryMask n used) (binaryMaskCount n used)
  | 0, false => FiniteCoding.ofEquiv binaryFalseZeroEquiv FiniteCoding.unit
  | 0, true => FiniteCoding.ofEquiv binaryTrueZeroEquiv FiniteCoding.empty
  | n + 1, false =>
      FiniteCoding.ofEquiv (binaryFalseSuccEquiv n) (binaryMaskCoding n false)
  | n + 1, true =>
      FiniteCoding.ofEquiv (binaryTrueSuccEquiv n)
        (FiniteCoding.sum (binaryMaskCoding n true)
          (FiniteCoding.sum (binaryMaskCoding n false) (binaryMaskCoding n true)))

theorem binaryMaskCount_false (n : Nat) : binaryMaskCount n false = 1 := by
  induction n with
  | zero => rfl
  | succ n ih => simpa [binaryMaskCount] using ih

theorem binaryMaskCount_true (n : Nat) :
    binaryMaskCount n true = 2 ^ n - 1 := by
  induction n with
  | zero => rfl
  | succ n ih =>
      rw [binaryMaskCount, ih, binaryMaskCount_false]
      rw [Nat.pow_succ]
      have hpow : 0 < 2 ^ n := Nat.two_pow_pos n
      omega

/-- Exact finite coding of free-AC product classes by the `2^n-1` nonempty
binary masks, obtained by transporting the recursively proved count. -/
def acProductClassCoding (n : Nat) :
    FiniteCoding (ACProductClass n) (2 ^ n - 1) :=
  FiniteCoding.castCard (binaryMaskCount_true n) (binaryMaskCoding n true)

theorem everyProductClassHasGenerator (c : ACProductClass n) :
    exists i : Fin n, c.assignment i = true :=
  ⟨c.witness, c.assignment_witness⟩

/-! ## Ternary assignments (binary operator nodes) -/

inductive Placement where
  | outside
  | left
  | right
  deriving DecidableEq, Repr

inductive Coverage where
  | neither
  | leftOnly
  | rightOnly
  | both
  deriving DecidableEq, Repr

/-- A ternary word classified by exactly which child tags it uses. Each
constructor prepends one of `outside`, `left`, or `right`; the result index is
the exact coverage state. -/
inductive TernaryAssignment : Nat -> Coverage -> Type where
  | nil : TernaryAssignment 0 .neither
  | outside : TernaryAssignment n coverage -> TernaryAssignment (n + 1) coverage
  | leftFresh : TernaryAssignment n .neither -> TernaryAssignment (n + 1) .leftOnly
  | leftAgain : TernaryAssignment n .leftOnly -> TernaryAssignment (n + 1) .leftOnly
  | leftCompletes : TernaryAssignment n .rightOnly -> TernaryAssignment (n + 1) .both
  | leftBoth : TernaryAssignment n .both -> TernaryAssignment (n + 1) .both
  | rightFresh : TernaryAssignment n .neither -> TernaryAssignment (n + 1) .rightOnly
  | rightAgain : TernaryAssignment n .rightOnly -> TernaryAssignment (n + 1) .rightOnly
  | rightCompletes : TernaryAssignment n .leftOnly -> TernaryAssignment (n + 1) .both
  | rightBoth : TernaryAssignment n .both -> TernaryAssignment (n + 1) .both

/-- A hash-consed binary AC operator node is an ordered left/right placement
with both children nonempty. -/
abbrev ACBinaryOperatorNode (n : Nat) := TernaryAssignment n .both

def TernaryAssignment.assignment :
    TernaryAssignment n coverage -> Fin n -> Placement
  | .nil, i => Fin.elim0 i
  | .outside tail, i => Fin.cases .outside tail.assignment i
  | .leftFresh tail, i => Fin.cases .left tail.assignment i
  | .leftAgain tail, i => Fin.cases .left tail.assignment i
  | .leftCompletes tail, i => Fin.cases .left tail.assignment i
  | .leftBoth tail, i => Fin.cases .left tail.assignment i
  | .rightFresh tail, i => Fin.cases .right tail.assignment i
  | .rightAgain tail, i => Fin.cases .right tail.assignment i
  | .rightCompletes tail, i => Fin.cases .right tail.assignment i
  | .rightBoth tail, i => Fin.cases .right tail.assignment i

def TernaryAssignment.leftOnlyWitness :
    (word : TernaryAssignment n .leftOnly) -> Fin n
  | .outside tail => tail.leftOnlyWitness.succ
  | .leftFresh _ => 0
  | .leftAgain _ => 0

def TernaryAssignment.rightOnlyWitness :
    (word : TernaryAssignment n .rightOnly) -> Fin n
  | .outside tail => tail.rightOnlyWitness.succ
  | .rightFresh _ => 0
  | .rightAgain _ => 0

def TernaryAssignment.bothLeftWitness :
    (word : TernaryAssignment n .both) -> Fin n
  | .outside tail => tail.bothLeftWitness.succ
  | .leftCompletes _ => 0
  | .leftBoth _ => 0
  | .rightCompletes tail => tail.leftOnlyWitness.succ
  | .rightBoth tail => tail.bothLeftWitness.succ

def TernaryAssignment.bothRightWitness :
    (word : TernaryAssignment n .both) -> Fin n
  | .outside tail => tail.bothRightWitness.succ
  | .leftCompletes tail => tail.rightOnlyWitness.succ
  | .leftBoth tail => tail.bothRightWitness.succ
  | .rightCompletes _ => 0
  | .rightBoth _ => 0

@[simp] theorem TernaryAssignment.leftOnlyWitness_spec
    (word : TernaryAssignment n .leftOnly) :
    word.assignment word.leftOnlyWitness = .left := by
  cases word with
  | outside tail => exact TernaryAssignment.leftOnlyWitness_spec tail
  | leftFresh tail => rfl
  | leftAgain tail => rfl

@[simp] theorem TernaryAssignment.rightOnlyWitness_spec
    (word : TernaryAssignment n .rightOnly) :
    word.assignment word.rightOnlyWitness = .right := by
  cases word with
  | outside tail => exact TernaryAssignment.rightOnlyWitness_spec tail
  | rightFresh tail => rfl
  | rightAgain tail => rfl

@[simp] theorem TernaryAssignment.bothLeftWitness_spec
    (word : TernaryAssignment n .both) :
    word.assignment word.bothLeftWitness = .left := by
  cases word with
  | outside tail => exact TernaryAssignment.bothLeftWitness_spec tail
  | leftCompletes tail => rfl
  | leftBoth tail => rfl
  | rightCompletes tail => exact tail.leftOnlyWitness_spec
  | rightBoth tail => exact TernaryAssignment.bothLeftWitness_spec tail

@[simp] theorem TernaryAssignment.bothRightWitness_spec
    (word : TernaryAssignment n .both) :
    word.assignment word.bothRightWitness = .right := by
  cases word with
  | outside tail => exact TernaryAssignment.bothRightWitness_spec tail
  | leftCompletes tail => exact tail.rightOnlyWitness_spec
  | leftBoth tail => exact TernaryAssignment.bothRightWitness_spec tail
  | rightCompletes tail => rfl
  | rightBoth tail => rfl

theorem binaryNodeUsesBothTags (node : ACBinaryOperatorNode n) :
    (exists i : Fin n, node.assignment i = .left) ∧
      exists i : Fin n, node.assignment i = .right :=
  ⟨⟨node.bothLeftWitness, node.bothLeftWitness_spec⟩,
    ⟨node.bothRightWitness, node.bothRightWitness_spec⟩⟩

/-- Constructor-derived cardinality of each exact coverage state. -/
def ternaryCoverageCount : Nat -> Coverage -> Nat
  | 0, .neither => 1
  | 0, .leftOnly => 0
  | 0, .rightOnly => 0
  | 0, .both => 0
  | n + 1, .neither => ternaryCoverageCount n .neither
  | n + 1, .leftOnly =>
      ternaryCoverageCount n .leftOnly +
        (ternaryCoverageCount n .neither + ternaryCoverageCount n .leftOnly)
  | n + 1, .rightOnly =>
      ternaryCoverageCount n .rightOnly +
        (ternaryCoverageCount n .neither + ternaryCoverageCount n .rightOnly)
  | n + 1, .both =>
      ternaryCoverageCount n .both +
        (ternaryCoverageCount n .rightOnly +
          (ternaryCoverageCount n .both +
            (ternaryCoverageCount n .leftOnly + ternaryCoverageCount n .both)))

private def ternaryNeitherZeroEquiv :
    TypeEquiv (TernaryAssignment 0 .neither) Unit where
  toFun
    | .nil => ()
  invFun _ := .nil
  left_inv
    | .nil => rfl
  right_inv _ := rfl

private def ternaryLeftZeroEquiv : TypeEquiv (TernaryAssignment 0 .leftOnly) Empty where
  toFun x := nomatch x
  invFun x := nomatch x
  left_inv x := nomatch x
  right_inv x := nomatch x

private def ternaryRightZeroEquiv : TypeEquiv (TernaryAssignment 0 .rightOnly) Empty where
  toFun x := nomatch x
  invFun x := nomatch x
  left_inv x := nomatch x
  right_inv x := nomatch x

private def ternaryBothZeroEquiv : TypeEquiv (TernaryAssignment 0 .both) Empty where
  toFun x := nomatch x
  invFun x := nomatch x
  left_inv x := nomatch x
  right_inv x := nomatch x

private def ternaryNeitherSuccEquiv (n : Nat) :
    TypeEquiv (TernaryAssignment (n + 1) .neither)
      (TernaryAssignment n .neither) where
  toFun
    | .outside tail => tail
  invFun := .outside
  left_inv
    | .outside _tail => rfl
  right_inv _ := rfl

private def ternaryLeftSuccEquiv (n : Nat) :
    TypeEquiv (TernaryAssignment (n + 1) .leftOnly)
      (Sum (TernaryAssignment n .leftOnly)
        (Sum (TernaryAssignment n .neither) (TernaryAssignment n .leftOnly))) where
  toFun
    | .outside tail => .inl tail
    | .leftFresh tail => .inr (.inl tail)
    | .leftAgain tail => .inr (.inr tail)
  invFun
    | .inl tail => .outside tail
    | .inr (.inl tail) => .leftFresh tail
    | .inr (.inr tail) => .leftAgain tail
  left_inv
    | .outside _tail => rfl
    | .leftFresh _tail => rfl
    | .leftAgain _tail => rfl
  right_inv
    | .inl _tail => rfl
    | .inr (.inl _tail) => rfl
    | .inr (.inr _tail) => rfl

private def ternaryRightSuccEquiv (n : Nat) :
    TypeEquiv (TernaryAssignment (n + 1) .rightOnly)
      (Sum (TernaryAssignment n .rightOnly)
        (Sum (TernaryAssignment n .neither) (TernaryAssignment n .rightOnly))) where
  toFun
    | .outside tail => .inl tail
    | .rightFresh tail => .inr (.inl tail)
    | .rightAgain tail => .inr (.inr tail)
  invFun
    | .inl tail => .outside tail
    | .inr (.inl tail) => .rightFresh tail
    | .inr (.inr tail) => .rightAgain tail
  left_inv
    | .outside _tail => rfl
    | .rightFresh _tail => rfl
    | .rightAgain _tail => rfl
  right_inv
    | .inl _tail => rfl
    | .inr (.inl _tail) => rfl
    | .inr (.inr _tail) => rfl

private def ternaryBothSuccEquiv (n : Nat) :
    TypeEquiv (TernaryAssignment (n + 1) .both)
      (Sum (TernaryAssignment n .both)
        (Sum (TernaryAssignment n .rightOnly)
          (Sum (TernaryAssignment n .both)
            (Sum (TernaryAssignment n .leftOnly) (TernaryAssignment n .both))))) where
  toFun
    | .outside tail => .inl tail
    | .leftCompletes tail => .inr (.inl tail)
    | .leftBoth tail => .inr (.inr (.inl tail))
    | .rightCompletes tail => .inr (.inr (.inr (.inl tail)))
    | .rightBoth tail => .inr (.inr (.inr (.inr tail)))
  invFun
    | .inl tail => .outside tail
    | .inr (.inl tail) => .leftCompletes tail
    | .inr (.inr (.inl tail)) => .leftBoth tail
    | .inr (.inr (.inr (.inl tail))) => .rightCompletes tail
    | .inr (.inr (.inr (.inr tail))) => .rightBoth tail
  left_inv
    | .outside _tail => rfl
    | .leftCompletes _tail => rfl
    | .leftBoth _tail => rfl
    | .rightCompletes _tail => rfl
    | .rightBoth _tail => rfl
  right_inv
    | .inl _tail => rfl
    | .inr (.inl _tail) => rfl
    | .inr (.inr (.inl _tail)) => rfl
    | .inr (.inr (.inr (.inl _tail))) => rfl
    | .inr (.inr (.inr (.inr _tail))) => rfl

/-- Coding assembled recursively from the ten ternary constructors. -/
def ternaryAssignmentCoding : (n : Nat) -> (coverage : Coverage) ->
    FiniteCoding (TernaryAssignment n coverage) (ternaryCoverageCount n coverage)
  | 0, .neither =>
      FiniteCoding.ofEquiv ternaryNeitherZeroEquiv FiniteCoding.unit
  | 0, .leftOnly =>
      FiniteCoding.ofEquiv ternaryLeftZeroEquiv FiniteCoding.empty
  | 0, .rightOnly =>
      FiniteCoding.ofEquiv ternaryRightZeroEquiv FiniteCoding.empty
  | 0, .both =>
      FiniteCoding.ofEquiv ternaryBothZeroEquiv FiniteCoding.empty
  | n + 1, .neither =>
      FiniteCoding.ofEquiv (ternaryNeitherSuccEquiv n)
        (ternaryAssignmentCoding n .neither)
  | n + 1, .leftOnly =>
      FiniteCoding.ofEquiv (ternaryLeftSuccEquiv n)
        (FiniteCoding.sum (ternaryAssignmentCoding n .leftOnly)
          (FiniteCoding.sum (ternaryAssignmentCoding n .neither)
            (ternaryAssignmentCoding n .leftOnly)))
  | n + 1, .rightOnly =>
      FiniteCoding.ofEquiv (ternaryRightSuccEquiv n)
        (FiniteCoding.sum (ternaryAssignmentCoding n .rightOnly)
          (FiniteCoding.sum (ternaryAssignmentCoding n .neither)
            (ternaryAssignmentCoding n .rightOnly)))
  | n + 1, .both =>
      FiniteCoding.ofEquiv (ternaryBothSuccEquiv n)
        (FiniteCoding.sum (ternaryAssignmentCoding n .both)
          (FiniteCoding.sum (ternaryAssignmentCoding n .rightOnly)
            (FiniteCoding.sum (ternaryAssignmentCoding n .both)
              (FiniteCoding.sum (ternaryAssignmentCoding n .leftOnly)
                (ternaryAssignmentCoding n .both)))))

theorem ternaryCoverageCount_neither (n : Nat) :
    ternaryCoverageCount n .neither = 1 := by
  induction n with
  | zero => rfl
  | succ n ih => simpa [ternaryCoverageCount] using ih

theorem ternaryCoverageCount_leftOnly (n : Nat) :
    ternaryCoverageCount n .leftOnly = 2 ^ n - 1 := by
  induction n with
  | zero => rfl
  | succ n ih =>
      rw [ternaryCoverageCount, ih, ternaryCoverageCount_neither]
      rw [Nat.pow_succ]
      have hpow : 0 < 2 ^ n := Nat.two_pow_pos n
      omega

theorem ternaryCoverageCount_rightOnly (n : Nat) :
    ternaryCoverageCount n .rightOnly = 2 ^ n - 1 := by
  induction n with
  | zero => rfl
  | succ n ih =>
      rw [ternaryCoverageCount, ih, ternaryCoverageCount_neither]
      rw [Nat.pow_succ]
      have hpow : 0 < 2 ^ n := Nat.two_pow_pos n
      omega

/-- The inclusion-exclusion subtraction is well formed in `Nat`, including
the edge case `n=0`. -/
theorem twoPowSucc_le_threePow_add_one (n : Nat) :
    2 ^ (n + 1) <= 3 ^ n + 1 := by
  induction n with
  | zero => decide
  | succ n ih =>
      simp only [Nat.pow_succ] at ih ⊢
      have hthree : 1 <= 3 ^ n := by exact Nat.one_le_pow n 3 (by decide)
      omega

/-- Exact count of ternary assignments using both left and right. We write
`3^n + 1 - 2^(n+1)` rather than left-associated natural subtraction, so the
formula also has the intended value zero at `n=0`. -/
theorem ternaryCoverageCount_both (n : Nat) :
    ternaryCoverageCount n .both = 3 ^ n + 1 - 2 ^ (n + 1) := by
  induction n with
  | zero => rfl
  | succ n ih =>
      rw [ternaryCoverageCount, ih, ternaryCoverageCount_rightOnly,
        ternaryCoverageCount_leftOnly]
      have hbound := twoPowSucc_le_threePow_add_one n
      have hboundSucc := twoPowSucc_le_threePow_add_one (n + 1)
      have htwo : 0 < 2 ^ n := Nat.two_pow_pos n
      simp only [Nat.pow_succ] at hbound hboundSucc ⊢
      omega

/-- Exact finite coding of binary AC operator nodes. This is derived from
the constructor coding and the closed-form theorem, not supplied as data. -/
def acBinaryOperatorNodeCoding (n : Nat) :
    FiniteCoding (ACBinaryOperatorNode n) (3 ^ n + 1 - 2 ^ (n + 1)) :=
  FiniteCoding.castCard (ternaryCoverageCount_both n)
    (ternaryAssignmentCoding n .both)

/-! ## Explicit constant-factor consequences -/

/-- A self-contained natural-number version of eventual constant-factor
equivalence.  It avoids importing an analytic asymptotics library while making
both directions and the threshold explicit. -/
def NatTheta (f g : Nat -> Nat) : Prop :=
  exists factor threshold : Nat, 0 < factor ∧
    forall n, threshold <= n ->
      f n <= factor * g n ∧ g n <= factor * f n

def productClassCount (n : Nat) : Nat := 2 ^ n - 1

def binaryOperatorNodeCount (n : Nat) : Nat :=
  3 ^ n + 1 - 2 ^ (n + 1)

/-- The exact `2^n-1` product-class count is Theta(`2^n`), witnessed by
factor two from threshold one. -/
theorem productClassCountThetaTwoPow :
    NatTheta productClassCount (fun n => 2 ^ n) := by
  refine ⟨2, 1, by decide, ?_⟩
  intro n hn
  have hn0 : n ≠ 0 := by omega
  have hpow : 1 < 2 ^ n := Nat.one_lt_pow hn0 (by decide)
  simp only [productClassCount]
  omega

private theorem binaryNodeLowerScale (n : Nat) (hn : 3 <= n) :
    3 * 2 ^ (n + 1) <= 2 * 3 ^ n + 3 := by
  induction n with
  | zero => omega
  | succ n ih =>
      by_cases htwo : n = 2
      · subst n
        decide
      · have hn' : 3 <= n := by omega
        have ih' := ih hn'
        have hthree : 1 <= 3 ^ n := Nat.one_le_pow n 3 (by decide)
        simp only [Nat.pow_succ] at ih' ⊢
        omega

/-- The exact inclusion-exclusion node count is Theta(`3^n`), witnessed by
factor three from threshold three. -/
theorem binaryOperatorNodeCountThetaThreePow :
    NatTheta binaryOperatorNodeCount (fun n => 3 ^ n) := by
  refine ⟨3, 3, by decide, ?_⟩
  intro n hn
  have hbound := twoPowSucc_le_threePow_add_one n
  have hscale := binaryNodeLowerScale n hn
  have htwo : 0 < 2 ^ (n + 1) := Nat.two_pow_pos (n + 1)
  simp only [binaryOperatorNodeCount]
  constructor <;> omega

/-- Atomic exact-count conclusion for the nonempty squarefree product classes. -/
theorem completeBinaryACProductClassCount (n : Nat) :
    Nonempty (FiniteCoding (ACProductClass n) (2 ^ n - 1)) :=
  ⟨acProductClassCoding n⟩

/-- Atomic exact-count conclusion for ordered disjoint nonempty child pairs. -/
theorem completeBinaryACOperatorNodeCount (n : Nat) :
    Nonempty (FiniteCoding (ACBinaryOperatorNode n)
      (3 ^ n + 1 - 2 ^ (n + 1))) :=
  ⟨acBinaryOperatorNodeCoding n⟩

/-- Paper claim F01 at exact finite-cardinality strength for the free
commutative semigroup on distinct generators, with no unit and no additional
equations. The two codings are constructive bijections, and node assignments
carry explicit witnesses for both ordered child tags. -/
theorem sizeOfCompleteBinaryACClosure (n : Nat) :
    Nonempty (FiniteCoding (ACProductClass n) (2 ^ n - 1)) ∧
      Nonempty (FiniteCoding (ACBinaryOperatorNode n)
        (3 ^ n + 1 - 2 ^ (n + 1))) :=
  ⟨completeBinaryACProductClassCount n,
    completeBinaryACOperatorNodeCount n⟩

/-- Named-paper wrapper F01: exact finite cardinalities together with the two
separately registered asymptotic consequences. -/
theorem completeBinaryACClosureCounts :
    (forall n : Nat,
      Nonempty (FiniteCoding (ACProductClass n) (2 ^ n - 1)) ∧
        Nonempty (FiniteCoding (ACBinaryOperatorNode n)
          (3 ^ n + 1 - 2 ^ (n + 1)))) ∧
      NatTheta productClassCount (fun n => 2 ^ n) ∧
        NatTheta binaryOperatorNodeCount (fun n => 3 ^ n) :=
  ⟨sizeOfCompleteBinaryACClosure,
    productClassCountThetaTwoPow,
    binaryOperatorNodeCountThetaThreePow⟩

end TypedSlottedEGraphsPaper.ACClosureCounts
