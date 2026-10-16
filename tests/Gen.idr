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
import Data.Bits
import Data.Fin
import Data.List
import Data.Nat
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

||| The cells drawn so far, the last first, and the cells ahead, the next
||| first; `overran` once a draw found no cell left.
export
data Tape : Type where
  MkTape : (source : Source) -> (1 done : Slots) -> (1 ahead : Slots) -> (overran : Bool) -> Tape

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
||| each case is reproducible alone; tests/toolchain/lib/prop.h seeds its
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
step (S k) (MkTape (Seeded s) done (Slot _ _ rest) overran) =
  let s' = s + gamma
      i = belowSucc k (integerToNat (mod (cast {to = Integer} (mix s')) (natToInteger (S k))))
  in i # MkTape (Seeded s') (Slot (finToNat i) (S k) done) rest overran
step (S k) (MkTape Replayed done (Slot v _ rest) overran) =
  let i = belowSucc k v in i # MkTape Replayed (Slot (finToNat i) (S k) done) rest overran
step (S k) (MkTape source done End _) = FZ # MkTape source done End True

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

mutual
  ||| The option whose span of the running total holds `r`: an earlier
  ||| option for a smaller draw, so 0 is the first option of weight above 0.
  pickIn : (ws : Vect n Nat) -> Fin (weightSum ws) -> Fin n
  pickIn [] FZ impossible
  pickIn [] (FS _) impossible
  pickIn (w :: ws) r = pickFrom w ws r

  ||| The option whose span holds `r`, of an option with `u` of its span
  ||| left and the options `ws` after it.
  pickFrom : (u : Nat) -> (ws : Vect n Nat) -> Fin (u + weightSum ws) -> Fin (S n)
  pickFrom Z ws r = FS (pickIn ws r)
  pickFrom (S _) _ FZ = FZ
  pickFrom (S u) ws (FS r) = pickFrom u ws r

||| An option, each as likely as its weight.
export
weighted : Weights n -> Gen (Fin n)
weighted (MkWeights ws) = pickIn ws <$> draw (weightSum ws)

||| Swarm testing: each weight zeroed with probability one half, but one
||| option, drawn by the weights, which keeps its own, so the result is a
||| distribution again; a tape of zeros keeps every weight.
export
swarm : Weights n -> Gen (Weights n)
swarm w@(MkWeights ws) = do
  keep <- weighted w
  coins <- traverse (\_ => draw 2) ws
  let ws' = zeroed keep coins ws
  -- The option kept has a weight above 0 (`weighted` picks no other), so
  -- the sum is above 0 and `No` cannot happen.
  pure $ case isItSucc (weightSum ws') of
    Yes nonzero => MkWeights ws'
    No _ => w
  where
    coin : Fin 2 -> Nat -> Nat
    coin FZ x = x
    coin (FS _) _ = 0

    zeroed : Fin m -> Vect m (Fin 2) -> Vect m Nat -> Vect m Nat
    zeroed FZ (_ :: cs) (x :: xs) = x :: zipWith coin cs xs
    zeroed (FS i) (c :: cs) (x :: xs) = coin c x :: zeroed i cs xs

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
  overran : Bool

||| A value, with the values of the cells done (the last first) put before
||| `tape`.
collect : a -> Bool -> (1 done : Slots) -> List Nat -> Drawn a
collect x overran End tape = MkDrawn x tape overran
collect x overran (Slot v _ older) tape = collect x overran older (v :: tape)

drawn : (1 _ : Res a (const Tape)) -> Drawn a
drawn (x # MkTape _ done ahead overran) = case release ahead of () => collect x overran done []

||| A case of a seed, on a tape of `capacity` cells.
export
seeded : (capacity : Nat) -> (seed : Bits64) -> Gen a -> Drawn a
seeded capacity seed (MkGen g) = drawn (g (MkTape (Seeded seed) End (blanks capacity) False))

||| A case of each seed, each with whether it overran, on one tape of
||| `capacity` cells that every seed reuses.
export
seededEach : (capacity : Nat) -> (seeds : List Bits64) -> Gen a -> List (a, Bool)
seededEach capacity seeds (MkGen g) = each seeds (blanks capacity) []
  where
    each : List Bits64 -> (1 _ : Slots) -> List (a, Bool) -> List (a, Bool)
    each [] cells cases = case release cells of () => reverse cases
    each (s :: ss) cells cases =
      let x # MkTape _ done ahead overran = g (MkTape (Seeded s) End cells False) in
      each ss (reverseOnto done ahead) ((x, overran) :: cases)

||| The case a recorded tape gives. A value past its bound is read as the
||| bound's last, and a tape too short as zeros, so every tape is a case.
export
replay : (tape : List Nat) -> Gen a -> Drawn a
replay tape (MkGen g) = drawn (g (MkTape Replayed End (slotsOf tape) False))

||| Every value of a generator, by the tapes that give them.
public export
record Box a where
  constructor MkBox
  values : List a
  whole : Bool

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
||| in the odometer's order, the first draw the slowest. `whole` when the
||| enumeration ended within `limit` runs and no run needed more cells.
export
exhaustive : (capacity : Nat) -> (limit : Nat) -> Gen a -> Box a
exhaustive capacity limit (MkGen g) = enumerate limit (blanks capacity) [] False
  where
    enumerate : Nat -> (1 _ : Slots) -> List a -> Bool -> Box a
    enumerate Z cells found _ = case release cells of () => MkBox (reverse found) False
    enumerate (S l) cells found over =
      let x # MkTape _ done ahead overran = g (MkTape Replayed End cells False) in
      case advance done ahead of
        Next cells' => enumerate l cells' (x :: found) (over || overran)
        Finished => MkBox (reverse (x :: found)) (not (over || overran))

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

||| The powers of two from the largest not above `n` down to 1.
spans : Nat -> List Nat
spans n = go n 1 []
  where
    -- Doubling `p` until it passes `n`, each power kept before the larger
    -- ones. `n` bounds the doublings structurally (2^n passes n), so the
    -- bound is never what ends them.
    go : Nat -> Nat -> List Nat -> List Nat
    go Z _ acc = acc
    go (S bound) p acc = if p > n then acc else go bound (2 * p) (p :: acc)

||| Smaller tapes than `t`, each strictly before it in shortlex order, in
||| the order a shrinker tries them: every span deleted, the longest first;
||| every span holding a value above 0 zeroed; every value halved; every
||| value above 1 decremented. Each pass is one sweep, left to right.
export
candidates : List Nat -> List (List Nat)
candidates t =
  let n = length t
      ls = spans n
  in [ take i t ++ drop (i + l) t | l <- ls, i <- [0 .. minus n l] ]
     ++ [ take i t ++ replicate l 0 ++ drop (i + l) t
        | l <- ls, i <- [0 .. minus n l], any (> 0) (take l (drop i t)) ]
     ++ [ take i t ++ div v 2 :: drop (S i) t | (i, v) <- zip [0 .. n] t, v > 0 ]
     ++ [ take i t ++ minus v 1 :: drop (S i) t | (i, v) <- zip [0 .. n] t, v > 1 ]

||| The smallest failing tape the candidates reach from `t`: the first
||| candidate that still fails is kept and the passes start again, until
||| none fails. Each tape kept is smaller in `length + sum` by at least 1,
||| so that sum bounds the rounds: it is the proof that shrinking ends,
||| never the reason it stops.
export
shrink : (stillFails : List Nat -> Bool) -> List Nat -> List Nat
shrink stillFails t = go (length t + sum t) t
  where
    go : Nat -> List Nat -> List Nat
    go Z u = u
    go (S bound) u = case find stillFails (candidates u) of
      Nothing => u
      Just smaller => go bound smaller

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

0 depWhole : (exhaustive 4 100 Gen.dep).whole = True
depWhole = Refl

0 depLimited : (exhaustive 4 3 Gen.dep).whole = False
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
  pure (finToNat a, finToNat b, finToNat c)

||| The values of the options a generator of options gives over every tape.
options : Box (Fin n) -> List Nat
options box = map finToNat box.values

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
     in r.value == d.value && r.tape == d.tape && not d.overran)
  | s <- [1, 2, 3] ] ++
  [ ("seededEach gives each seed's case on one tape",
     let seeds = [1, 2, 3]
     in seededEach 16 seeds mixed == map (\s => let d = seeded 16 s mixed in (d.value, d.overran)) seeds)
  , ("every tape of pair: six values",
     let box = exhaustive 4 100 pair in length box.values == 6 && box.whole)
  , ("every tape of dep, in the odometer's order",
     let box = exhaustive 4 100 dep in box.values == [0, 0, 1, 0, 1, 2] && box.whole)
  , ("an enumeration past its limit is not whole", not (exhaustive 4 3 dep).whole)
  , ("an enumeration past its capacity is not whole", not (exhaustive 1 100 pair).whole)
  , ("weighted picks by the running total, never an option of weight 0",
     options (exhaustive 2 100 (weighted (MkWeights [2, 0, 1]))) == [0, 0, 2])
  , ("swarm zeroes every option on some tape and keeps it on another",
     let results = map (\(MkWeights ws) => toList ws) (exhaustive 8 1000 (swarm (MkWeights [1, 1, 1]))).values
     in all (\i => any (\ws => getAt i ws == Just 0) results && any (\ws => getAt i ws == Just 1) results)
            (the (List Nat) [0, 1, 2]))
  , ("every candidate is before its tape in shortlex order",
     all (\t => all (\c => shortlex c t) (candidates t)) (the (List (List Nat)) [[7, 0, 9, 4], [0, 0, 1], [3]]))
  , ("shrinking ends at a failing tape no candidate of which fails",
     let fails = \t => sum t >= 10
         small = shrink fails [7, 0, 9, 4]
     in fails small && not (any fails (candidates small)))
  , ("a draw's loop sums the same seeded and replayed",
     let loop = MkGen (drawLoop 20 7 0)
         d = seeded 20 5 loop
     in (replay d.tape loop).value == d.value)
  ]
