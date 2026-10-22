-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Generators over a choice stream. A generator reads every decision as a
||| natural below a bound from one tape; where the values on the tape come
||| from is the tape's source, never the generator's:
|||
||| - `seeded`: splitmix64 from a seed fills it, a draw at a time;
||| - `replay`: a recorded tape gives back the case it recorded;
||| - `exhaustive`: an odometer runs the generator on every tape, in order,
|||   up to a size, so a small scope is checked whole.
|||
||| A failing case shrinks by its tape (`shrink`): every candidate is
||| strictly smaller in shortlex order, and is a valid case because the
||| generator makes it again.
|||
||| The tape is linear data, one cell per draw, allocated once per run: a
||| draw takes the next cell apart and builds it again with what it read, so
||| where cells are reused in place a draw allocates nothing. The module is
||| in the language idris-mlir compiles, and the stock Idris runs it too.
module Gen

import Prelude
import Control.WellFounded
import Data.Bits
import Data.DPair
import Data.Fin
import Data.List
import Data.Nat
import Data.Nat.Views
import Data.SnocList
import Data.So
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The tape
------------------------------------------------------------------------------

||| The tape's cells, one per draw: the value drawn there and the bound it
||| was drawn below. A cell no draw has written yet is `Slot 0 0`, or holds
||| a value to replay with bound 0.
data Slots : Type where
  End : Slots
  Slot : (value : Nat) -> (bound : Nat) -> (1 rest : Slots) -> Slots

||| Where a draw's value comes from: splitmix64's state, or the cell itself.
data Source = Seeded Bits64 | Replayed

||| Whether a run's draws all found a cell: within its tape, or past its
||| end, where each draw past it was the smallest value, so the case is
||| valid but not the one its source would have drawn.
public export
data Fit = Within | Overran

public export
Eq Fit where
  Within == Within = True
  Overran == Overran = True
  _ == _ = False

||| Of two runs' fits, the fit of both.
past : Fit -> Fit -> Fit
past Within fit = fit
past Overran _ = Overran

||| The cells drawn so far, the last first, and the cells ahead, the next
||| first; `fit`, Overran once a draw found no cell left.
export
data Tape : Type where
  MkTape : (source : Source) -> (1 done : Slots) -> (1 ahead : Slots) -> (fit : Fit) -> Tape

||| A generator: what it does to a tape, which it gives back.
public export
record Gen a where
  constructor MkGen
  run : (1 _ : Tape) -> Res a (const Tape)

export
Functor Gen where
  map f (MkGen g) = MkGen (\t => let x # t' = g t in f x # t')

export
Applicative Gen where
  pure x = MkGen (\t => x # t)
  MkGen f <*> MkGen g = MkGen (\t => let h # t1 = f t; x # t2 = g t1 in h x # t2)

export
Monad Gen where
  MkGen g >>= k = MkGen (\t => let x # t1 = g t; MkGen h = k x in h t1)

------------------------------------------------------------------------------
-- splitmix64
------------------------------------------------------------------------------

||| splitmix64's increment: the odd integer nearest 2^64 divided by the
||| golden ratio.
public export
gamma : Bits64
gamma = 0x9E3779B97F4A7C15

||| splitmix64's output function, the state's mix.
public export
mix : Bits64 -> Bits64
mix z =
  let z1 = xor z (shiftR z 30) * 0xBF58476D1CE4E5B9
      z2 = xor z1 (shiftR z1 27) * 0x94D049BB133111EB
  in xor z2 (shiftR z2 31)

||| Output `i` of splitmix64 started at `s`, counting from 0: the state
||| after `i + 1` steps of `gamma`, mixed. The case seeds of a run, so that
||| each case is reproducible alone; harness/prop/prop.h seeds its
||| cases by the same definition.
public export
caseSeed : Bits64 -> Nat -> Bits64
caseSeed s i = mix (s + cast (S i) * gamma)

------------------------------------------------------------------------------
-- A draw
------------------------------------------------------------------------------

||| A case analysis of a Boolean that keeps the evidence. Base's `choose`
||| is exported without its body, so a check at compile time could not
||| reduce through it.
decide : (b : Bool) -> Either (So b) (So (not b))
decide True = Left Oh
decide False = Right Oh

||| `v` below `S k`, or `k`, the largest, when it is not: a replayed value
||| past its bound is the bound's last.
belowSucc : (k : Nat) -> Nat -> Fin (S k)
belowSucc k v = case decide (v < S k) of
  Left below => natToFinLT v {prf = ltOpReflectsLT v (S k) below}
  Right _ => natToFinLT k {prf = Control.Relation.reflexive}

||| One draw below `n`: the next cell ahead, read and written with the value
||| drawn and its bound, moves onto the cells done. With no cell ahead the
||| draw is the smallest, and the tape says it overran.
step : (n : Nat) -> {auto 0 nonzero : IsSucc n} -> (1 _ : Tape) -> Res (Fin n) (const Tape)
step Z {nonzero = ItIsSucc} _ impossible
step (S k) (MkTape (Seeded s) done (Slot _ _ rest) fit) =
  let s' = s + gamma
      i = belowSucc k (integerToNat (mod (cast {to = Integer} (mix s')) (natToInteger (S k))))
  in i # MkTape (Seeded s') (Slot (finToNat i) (S k) done) rest fit
step (S k) (MkTape Replayed done (Slot v _ rest) fit) =
  let i = belowSucc k v in i # MkTape Replayed (Slot (finToNat i) (S k) done) rest fit
step (S k) (MkTape source done End _) = FZ # MkTape source done End Overran

||| A draw below `n`, which is not 0: every value below it is a choice.
export
draw : (n : Nat) -> {auto 0 nonzero : IsSucc n} -> Gen (Fin n)
draw n = MkGen (step n)

||| One of a list that is not empty, given as its head and its tail, each
||| equally likely.
export
oneOf : a -> List a -> Gen a
oneOf x xs = pick (x :: xs) <$> draw (S (length xs))
  where
    pick : (ys : List a) -> Fin (length ys) -> a
    pick (y :: _) FZ = y
    pick (_ :: ys) (FS i) = pick ys i

------------------------------------------------------------------------------
-- Weights
------------------------------------------------------------------------------

public export
weightSum : Vect n Nat -> Nat
weightSum [] = 0
weightSum (w :: ws) = w + weightSum ws

||| A distribution over `n` options: a weight each, not all 0, which the
||| type keeps, so a draw always has an option to pick.
public export
data Weights : Nat -> Type where
  MkWeights : (ws : Vect n Nat) -> {auto 0 nonzero : IsSucc (weightSum ws)} -> Weights n

||| The weights, when they are not all 0.
export
weightsOf : (ws : Vect n Nat) -> Maybe (Weights n)
weightsOf ws = case isItSucc (weightSum ws) of
  Yes nonzero => Just (MkWeights ws)
  No _ => Nothing

||| The weights themselves.
public export
weightsOf' : Weights n -> Vect n Nat
weightsOf' (MkWeights ws) = ws

||| What is at least a successor is a successor.
0 above : LTE (S k) w -> IsSucc w
above (LTESucc _) = ItIsSucc

mutual
  ||| The option whose span of the running total holds `r`, with the proof
  ||| that its weight is above 0: an earlier option for a smaller draw, so
  ||| 0 is the first option of weight above 0.
  pickIn : (ws : Vect n Nat) -> Fin (weightSum ws) -> Subset (Fin n) (\i => IsSucc (index i ws))
  pickIn [] FZ impossible
  pickIn [] (FS _) impossible
  pickIn (w :: ws) r = pickFrom w ws reflexive r

  ||| The option whose span holds `r`, of an option of weight `w` with `u`
  ||| of its span left and the options `ws` after it: the option itself
  ||| when `r` is in what is left of its span, which is then not empty.
  pickFrom : (u : Nat) -> {0 w : Nat} -> (ws : Vect n Nat) -> (0 _ : LTE u w) ->
             Fin (u + weightSum ws) -> Subset (Fin (S n)) (\i => IsSucc (index i (w :: ws)))
  pickFrom Z ws _ r = let Element i positive = pickIn ws r in Element (FS i) positive
  pickFrom (S _) _ left FZ = Element FZ (above left)
  pickFrom (S u) ws left (FS r) = pickFrom u ws (lteSuccLeft left) r

||| An option, each as likely as its weight, which is above 0.
export
weighted : (w : Weights n) -> Gen (Subset (Fin n) (\i => IsSucc (index i (weightsOf' w))))
weighted (MkWeights ws) = pickIn ws <$> draw (weightSum ws)

coin : Fin 2 -> Nat -> Nat
coin FZ x = x
coin (FS _) _ = 0

||| The weights, each zeroed by its coin, but the kept option's.
zeroed : Fin m -> Vect m (Fin 2) -> Vect m Nat -> Vect m Nat
zeroed FZ (_ :: cs) (x :: xs) = x :: zipWith coin cs xs
zeroed (FS i) (c :: cs) (x :: xs) = coin c x :: zeroed i cs xs

||| `zeroed` keeps the kept option's weight.
0 keeps : (i : Fin m) -> (cs : Vect m (Fin 2)) -> (xs : Vect m Nat) -> index i (zeroed i cs xs) = index i xs
keeps FZ (_ :: _) (_ :: _) = Refl
keeps (FS i) (_ :: cs) (_ :: xs) = keeps i cs xs

||| An option of weight above 0 makes the weights' sum above 0.
0 positiveSum : (i : Fin m) -> (xs : Vect m Nat) -> IsSucc (index i xs) -> IsSucc (weightSum xs)
positiveSum FZ (S _ :: _) ItIsSucc = ItIsSucc
positiveSum (FS i) (x :: xs) positive = after x (positiveSum i xs positive)
  where
    after : (a : Nat) -> IsSucc b -> IsSucc (a + b)
    after a {b = S k} ItIsSucc = rewrite sym (plusSuccRightSucc a k) in ItIsSucc

||| Swarm testing: each weight zeroed with probability one half, but one
||| option, drawn by the weights, which keeps its own, so the result is a
||| distribution again; a tape of zeros keeps every weight.
export
swarm : Weights n -> Gen (Weights n)
swarm w@(MkWeights ws) = do
  Element keep positive <- weighted w
  coins <- traverse (\_ => draw 2) ws
  pure (MkWeights (zeroed keep coins ws)
          {nonzero = positiveSum keep (zeroed keep coins ws) (rewrite keeps keep coins ws in positive)})

------------------------------------------------------------------------------
-- Running a generator
------------------------------------------------------------------------------

||| `n` cells no draw has written.
blanks : Nat -> Slots
blanks Z = End
blanks (S n) = Slot 0 0 (blanks n)

||| A recorded tape's cells, to replay.
slotsOf : List Nat -> Slots
slotsOf [] = End
slotsOf (v :: vs) = Slot v 0 (slotsOf vs)

||| The cells of the first, last first, before the second: the cells done
||| put back ahead, in the order they were drawn, in one sweep.
reverseOnto : (1 _ : Slots) -> (1 _ : Slots) -> Slots
reverseOnto End ahead = ahead
reverseOnto (Slot v b rest) ahead = reverseOnto rest (Slot v b ahead)

||| Cells no run reads again, let go of.
release : (1 _ : Slots) -> ()
release End = ()
release (Slot _ _ rest) = release rest

||| A generator's value, with the values it drew.
public export
record Drawn a where
  constructor MkDrawn
  value : a
  tape : List Nat
  fit : Fit

||| A value, with the values of the cells done (the last first) put before
||| `tape`.
collect : a -> Fit -> (1 done : Slots) -> List Nat -> Drawn a
collect x fit End tape = MkDrawn x tape fit
collect x fit (Slot v _ older) tape = collect x fit older (v :: tape)

drawn : (1 _ : Res a (const Tape)) -> Drawn a
drawn (x # MkTape _ done ahead fit) = case release ahead of () => collect x fit done []

||| A case of a seed, on a tape of `capacity` cells.
export
seeded : (capacity : Nat) -> (seed : Bits64) -> Gen a -> Drawn a
seeded capacity seed (MkGen g) = drawn (g (MkTape (Seeded seed) End (blanks capacity) Within))

||| A case of each seed, each with its tape's fit, on one tape of
||| `capacity` cells that every seed reuses.
export
seededEach : (capacity : Nat) -> (seeds : List Bits64) -> Gen a -> List (a, Fit)
seededEach capacity seeds (MkGen g) = each seeds (blanks capacity) []
  where
    each : List Bits64 -> (1 _ : Slots) -> List (a, Fit) -> List (a, Fit)
    each [] cells cases = case release cells of () => reverse cases
    each (s :: ss) cells cases =
      let x # MkTape _ done ahead fit = g (MkTape (Seeded s) End cells Within) in
      each ss (reverseOnto done ahead) ((x, fit) :: cases)

||| The case a recorded tape gives. A value past its bound is read as the
||| bound's last, and a tape too short as zeros, so every tape is a case.
export
replay : (tape : List Nat) -> Gen a -> Drawn a
replay tape (MkGen g) = drawn (g (MkTape Replayed End (slotsOf tape) Within))

||| Whether an enumeration gave every value: whole, when it ended within
||| its limit and no run needed more cells than its tape has; or partial.
public export
data Coverage = Whole | Partial

public export
Eq Coverage where
  Whole == Whole = True
  Partial == Partial = True
  _ == _ = False

||| Every value of a generator, by the tapes that give them.
public export
record Box a where
  constructor MkBox
  values : List a
  coverage : Coverage

||| The odometer's next tape after a run, or none.
data Advance : Type where
  Next : (1 ahead : Slots) -> Advance
  Finished : Advance

||| The next tape: from the last draw back, a cell whose value is its
||| bound's last is zeroed, and the first that is not is incremented; the
||| cells before it keep their values. Cells past the last draw are zeros
||| already: a run draws every cell up to the one incremented before it,
||| and every cell after that one was zeroed.
advance : (1 done : Slots) -> (1 ahead : Slots) -> Advance
advance End ahead = case release ahead of () => Finished
advance (Slot v b older) ahead =
  if S v < b then Next (reverseOnto older (Slot (S v) b ahead))
             else advance older (Slot 0 0 ahead)

||| The values of a generator on every tape of at most `capacity` draws,
||| in the odometer's order, the first draw the slowest. Whole when the
||| enumeration ended within `limit` runs and no run needed more cells.
export
exhaustive : (capacity : Nat) -> (limit : Nat) -> Gen a -> Box a
exhaustive capacity limit (MkGen g) = enumerate limit (blanks capacity) [] Within
  where
    coverageOf : Fit -> Coverage
    coverageOf Within = Whole
    coverageOf Overran = Partial

    enumerate : Nat -> (1 _ : Slots) -> List a -> Fit -> Box a
    enumerate Z cells found _ = case release cells of () => MkBox (reverse found) Partial
    enumerate (S l) cells found sofar =
      let x # MkTape _ done ahead fit = g (MkTape Replayed End cells Within) in
      case advance done ahead of
        Next cells' => enumerate l cells' (x :: found) (past sofar fit)
        Finished => MkBox (reverse (x :: found)) (coverageOf (past sofar fit))

------------------------------------------------------------------------------
-- Shrinking
------------------------------------------------------------------------------

||| `a` before `b`: shorter, or as long and lexicographically smaller.
public export
shortlex : List Nat -> List Nat -> Bool
shortlex a b = case compare (length a) (length b) of
  LT => True
  EQ => a < b
  GT => False

||| A span of `S k` cells written as its `k`: twice the span, so written.
twice : Nat -> Nat
twice k = S (k + k)

||| The spans a shrinker takes from a tape of `n` cells: the powers of two
||| up to `n`, the largest first, each `S k` written as its `k`, so that no
||| span is empty. None for no cell; else twice those up to half of `n`,
||| then one.
spans : (n : Nat) -> SnocList Nat
spans n with (halfRec n)
  spans 0 | HalfRecZ = [<]
  spans (k + k) | HalfRecEven k rec = map twice (spans k | rec) :< 0
  spans (S (k + k)) | HalfRecOdd k rec = map twice (spans k | rec) :< 0

||| The values of a tape, summed: a structural sum, which proofs reduce.
export
tapeSum : List Nat -> Nat
tapeSum [] = 0
tapeSum (v :: vs) = v + tapeSum vs

||| What every candidate of a tape makes smaller: its length plus its sum.
export
measure : List Nat -> Nat
measure t = length t + tapeSum t

||| A candidate of `t` is smaller in its measure.
public export
Below : List Nat -> List Nat -> Type
Below t c = LT (measure c) (measure t)

0 shuffle : (a, b, c : Nat) -> a + (b + c) = b + (a + c)
shuffle a b c =
  rewrite plusAssociative a b c in
  rewrite plusCommutative a b in
  sym (plusAssociative b a c)

0 measureCons : (v : Nat) -> (vs : List Nat) -> measure (v :: vs) = S (v + measure vs)
measureCons v vs = cong S (shuffle (length vs) v (tapeSum vs))

0 measureAppend : (xs, ys : List Nat) -> measure (xs ++ ys) = measure xs + measure ys
measureAppend [] ys = Refl
measureAppend (x :: xs) ys =
  trans (measureCons x (xs ++ ys)) $
  trans (cong (\m => S (x + m)) (measureAppend xs ys)) $
  trans (cong S (plusAssociative x (measure xs) (measure ys))) $
  cong (+ measure ys) (sym (measureCons x xs))

0 shorter : (mb, ms', ms, ma : Nat) -> LTE (S ms') ms -> LTE (S (mb + (ms' + ma))) (mb + (ms + ma))
shorter mb ms' ms ma smaller =
  rewrite plusSuccRightSucc mb (ms' + ma) in
  plusLteMonotoneLeft mb (S (ms' + ma)) (ms + ma) (plusLteMonotoneRight ma (S ms') ms smaller)

||| A span replaced by a smaller one makes the tape around it smaller.
0 replaced : (b, s, s', a : List Nat) -> LT (measure s') (measure s) ->
             LT (measure (b ++ s' ++ a)) (measure (b ++ s ++ a))
replaced b s s' a smaller =
  replace {p = \m => LT m (measure (b ++ s ++ a))}
          (sym (trans (measureAppend b (s' ++ a)) (cong (measure b +) (measureAppend s' a)))) $
  replace {p = \m => LT (measure b + (measure s' + measure a)) m}
          (sym (trans (measureAppend b (s ++ a)) (cong (measure b +) (measureAppend s a)))) $
  shorter (measure b) (measure s') (measure s) (measure a) smaller

||| A cell made smaller makes its span smaller.
0 cellBelow : (h, y : Nat) -> (ys : List Nat) -> LT h y -> LT (measure (h :: ys)) (measure (y :: ys))
cellBelow h y ys smaller =
  replace {p = \m => LT m (measure (y :: ys))} (sym (measureCons h ys)) $
  replace {p = \m => LT (S (h + measure ys)) m} (sym (measureCons y ys)) $
  LTESucc (plusLteMonotoneRight (measure ys) (S h) y smaller)

||| A span zeroed is smaller when it held a value above 0.
0 zeroedBelow : (s : List Nat) -> IsSucc (tapeSum s) -> LT (measure (replicate (length s) 0)) (measure s)
zeroedBelow s positive =
  replace {p = \m => LT m (measure s)}
          (sym (trans (cong2 (+) (lengthReplicate {x = Z} (length s)) (zeros (length s)))
                      (plusZeroRightNeutral (length s)))) $
  lessThanPlus (length s) positive
  where
    zeros : (n : Nat) -> tapeSum (replicate n 0) = 0
    zeros Z = Refl
    zeros (S n) = zeros n
    lessThanPlus : (n : Nat) -> IsSucc m -> LT n (n + m)
    lessThanPlus n {m = S j} ItIsSucc = rewrite sym (plusSuccRightSucc n j) in LTESucc (lteAddRight n)

||| `k` less any amount is below `S k`: subtraction stops at 0.
0 leftBelow : (k, q : Nat) -> LT (minus k q) (S k)
leftBelow Z _ = LTESucc LTEZero
leftBelow (S k) Z = reflexive
leftBelow (S k) (S q) = lteSuccRight (leftBelow k q)

||| A tape cut around a span of at least one cell: the cells before it, the
||| span's first cell and the rest of it, and the cells after it.
data Cut : List Nat -> Type where
  MkCut : {0 t : List Nat} -> (before : List Nat) -> (first : Nat) -> (rest : List Nat) -> (after : List Nat) ->
          (0 whole : before ++ first :: rest ++ after = t) -> Cut t

||| A tape's first cells, at least one, and the cells after them.
data Front : List Nat -> Type where
  MkFront : {0 t : List Nat} -> (first : Nat) -> (rest : List Nat) -> (after : List Nat) ->
            (0 whole : first :: rest ++ after = t) -> Front t

||| The first `S k` cells of a tape, when it has that many.
front : (k : Nat) -> (t : List Nat) -> Maybe (Front t)
front _ [] = Nothing
front Z (x :: xs) = Just (MkFront x [] xs Refl)
front (S k) (x :: xs) = map (\(MkFront y ys a whole) => MkFront x (y :: ys) a (cong (x ::) whole)) (front k xs)

||| A cut of a tape, of that tape with one more cell before it.
behind : (x : Nat) -> Cut t -> Cut (x :: t)
behind x (MkCut b y ys a whole) = MkCut (x :: b) y ys a (cong (x ::) whole)

||| Every cut of a tape around a span of `S k` cells: the span from the
||| first cell, then from each cell after, while the tape holds it.
windows : (k : Nat) -> (t : List Nat) -> List (Cut t)
windows _ [] = []
windows k (x :: xs) = case front k (x :: xs) of
  Nothing => []
  Just (MkFront y ys a whole) => MkCut [] y ys a whole :: map (behind x) (windows k xs)

||| The span deleted.
deleted : Cut t -> Subset (List Nat) (Below t)
deleted (MkCut b y ys a whole) =
  Element (b ++ a) (replace {p = \u => Below u (b ++ a)} whole (replaced b (y :: ys) [] a (LTESucc LTEZero)))

||| The span zeroed, when it holds a value above 0.
zeroedSpan : Cut t -> Maybe (Subset (List Nat) (Below t))
zeroedSpan (MkCut b y ys a whole) = case isItSucc (tapeSum (y :: ys)) of
  Yes positive => Just (Element (b ++ replicate (length (y :: ys)) 0 ++ a)
                         (replace {p = \u => Below u (b ++ replicate (length (y :: ys)) 0 ++ a)} whole
                                  (replaced b (y :: ys) (replicate (length (y :: ys)) 0) a (zeroedBelow (y :: ys) positive))))
  No _ => Nothing

||| The span's first cell halved, rounding down, when it is above 0: `S k`
||| halved is `k` less half of `k`, and `k` less any amount is below `S k`,
||| so the proof never reads the division that sizes the half. The division
||| is one step of the runtime's on either host, where a recursion on the
||| cell would take as many steps as the cell holds.
halved : Cut t -> Maybe (Subset (List Nat) (Below t))
halved (MkCut b Z ys a whole) = Nothing
halved (MkCut b (S k) ys a whole) =
  Just (Element (b ++ half :: ys ++ a)
                (replace {p = \u => Below u (b ++ half :: ys ++ a)} whole
                         (replaced b (S k :: ys) (half :: ys) a (cellBelow half (S k) ys (leftBelow k halfOfK)))))
  where
    halfOfK : Nat
    halfOfK = integerToNat (div (natToInteger k) 2)
    half : Nat
    half = minus k halfOfK

||| The span's first cell less one, when it is above 1.
decremented : Cut t -> Maybe (Subset (List Nat) (Below t))
decremented (MkCut b (S (S k)) ys a whole) =
  Just (Element (b ++ S k :: ys ++ a)
                (replace {p = \u => Below u (b ++ S k :: ys ++ a)} whole
                         (replaced b (S (S k) :: ys) (S k :: ys) a (cellBelow (S k) (S (S k)) ys reflexive))))
decremented _ = Nothing

||| Smaller tapes than `t`, each with the proof that its length plus its
||| sum is smaller, in the order a shrinker tries them: every span deleted,
||| the longest first; every span holding a value above 0 zeroed; every
||| value above 0 halved; every value above 1 decremented. Each pass is one
||| sweep, left to right. Each is also before `t` in shortlex order.
export
candidates : (t : List Nat) -> List (Subset (List Nat) (Below t))
candidates t =
  let ks = spans (length t) <>> []
      cells = windows 0 t in
  (ks >>= \k => map deleted (windows k t))
  ++ (ks >>= \k => mapMaybe zeroedSpan (windows k t))
  ++ mapMaybe halved cells
  ++ mapMaybe decremented cells

||| Tapes sized by their measure, which every candidate makes smaller.
public export
[byMeasure] Sized (List Nat) where
  size = measure

||| The smallest failing tape the candidates reach from `t`: the first
||| candidate that still fails is kept and the passes start again, until
||| none fails. Each tape kept is smaller in its length plus its sum, which
||| its candidate proves: that is why shrinking ends.
export
shrink : (stillFails : List Nat -> Bool) -> List Nat -> List Nat
shrink stillFails t = go t (sizeAccessible @{Gen.byMeasure} t)
  where
    go : (u : List Nat) -> (0 _ : SizeAccessible @{Gen.byMeasure} u) -> List Nat
    go u (Access rec) = case find (stillFails . fst) (candidates u) of
      Nothing => u
      Just (Element smaller below) => go smaller (rec smaller below)

------------------------------------------------------------------------------
-- Gen's own checks
------------------------------------------------------------------------------

pair : Gen (Fin 3, Fin 2)
pair = [| (draw 3, draw 2) |]

||| A bound that depends on an earlier draw.
dep : Gen Nat
dep = do
  k <- draw 3
  j <- draw (S (finToNat k))
  pure (finToNat j)

0 pairCount : length (exhaustive 4 100 Gen.pair).values = 6
pairCount = Refl

0 depValues : (exhaustive 4 100 Gen.dep).values = [0, 0, 1, 0, 1, 2]
depValues = Refl

0 depWhole : (exhaustive 4 100 Gen.dep).coverage = Whole
depWhole = Refl

0 depLimited : (exhaustive 4 3 Gen.dep).coverage = Partial
depLimited = Refl

0 replayPast : (replay [7, 9] Gen.pair).value = (2, 1)
replayPast = Refl

||| `k` draws below `n` through `step`, summed: the draw's loop as a
||| function of its own, which idris-mlir must compile to cells reused in
||| place, taken apart without a test and counted nowhere.
drawLoop : (k : Nat) -> (n : Nat) -> {auto 0 _ : IsSucc n} -> Nat -> (1 _ : Tape) -> Res Nat (const Tape)
drawLoop Z _ acc t = acc # t
drawLoop (S k) n acc t = let i # t' = step n t in drawLoop k n (acc + finToNat i) t'

||| A generator of everything a draw can be: a plain draw, a weighted one,
||| and a draw whose bound an earlier one chose.
mixed : Gen (Nat, Nat, Nat)
mixed = do
  a <- draw 5
  b <- weighted (MkWeights [1, 3, 0, 2])
  c <- draw (S (finToNat a))
  pure (finToNat a, finToNat b.fst, finToNat c)

||| The values of the options a generator of options gives over every tape.
options : Box (Subset (Fin n) p) -> List Nat
options box = map (finToNat . fst) box.values

||| Gen's checks, each a name and whether it holds. Both hosts run them, so
||| what idris-mlir computes of Bits64 and of a tape is held to the stock
||| Idris's.
export
checks : List (String, Bool)
checks =
  [ ("splitmix64 from state 0, output 0", caseSeed 0 0 == 0xE220A8397B1DCDAF)
  , ("splitmix64 from state 0, output 1", caseSeed 0 1 == 0x6E789E6AA1B965F4)
  , ("splitmix64 from state 0, output 2", caseSeed 0 2 == 0x06C45D188009454F)
  ] ++
  [ ("replaying the tape of seed " ++ show s ++ " gives its case",
     let d = seeded 16 s mixed
         r = replay d.tape mixed
     in r.value == d.value && r.tape == d.tape && d.fit == Within)
  | s <- [1, 2, 3] ] ++
  [ ("seededEach gives each seed's case on one tape",
     let seeds = [1, 2, 3]
     in seededEach 16 seeds mixed == map (\s => let d = seeded 16 s mixed in (d.value, d.fit)) seeds)
  , ("every tape of pair: six values",
     let box = exhaustive 4 100 pair in length box.values == 6 && box.coverage == Whole)
  , ("every tape of dep, in the odometer's order",
     let box = exhaustive 4 100 dep in box.values == [0, 0, 1, 0, 1, 2] && box.coverage == Whole)
  , ("an enumeration past its limit is not whole", (exhaustive 4 3 dep).coverage == Partial)
  , ("an enumeration past its capacity is not whole", (exhaustive 1 100 pair).coverage == Partial)
  , ("weighted picks by the running total, never an option of weight 0",
     options (exhaustive 2 100 (weighted (MkWeights [2, 0, 1]))) == [0, 0, 2])
  , ("swarm zeroes every option on some tape and keeps it on another",
     let results = map weightsOf' (exhaustive 8 1000 (swarm (MkWeights [1, 1, 1]))).values
     in all (\i => any (\ws => index i ws == 0) results && any (\ws => index i ws == 1) results)
            (the (List (Fin 3)) [0, 1, 2]))
  , ("every candidate is before its tape in shortlex order",
     all (\t => all (\c => shortlex c.fst t) (candidates t)) (the (List (List Nat)) [[7, 0, 9, 4], [0, 0, 1], [3]]))
  , ("shrinking ends at a failing tape no candidate of which fails",
     let fails = \t => sum t >= 10
         small = shrink fails [7, 0, 9, 4]
     in fails small && not (any (fails . fst) (candidates small)))
  , ("a draw's loop sums the same seeded and replayed",
     let loop = MkGen (drawLoop 20 7 0)
         d = seeded 20 5 loop
     in (replay d.tape loop).value == d.value)
  ]
