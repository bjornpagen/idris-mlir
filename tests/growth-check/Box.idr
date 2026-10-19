-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The growth check (`check`) against brute force, on every graph of up to
||| three positions over a few weights, caps on some, and on hand cases.
||| The brute force reads Proof.Growth's definitions alone: simple cycles, sums by
||| cross-addition, components as mutual reach over every arc between
||| positions, and the least potential as the heaviest simple walk.
module Main

import IdrisMLIR.Proof.Growth
import IdrisMLIR.Frontend.Growth.Check

import Data.Fin
import Data.List
import Data.List1
import Data.String
import Data.Vect

%default total

isStuck : Label -> Bool
isStuck Unmeasured = True
isStuck (Measured _ _) = False

finite : Label -> Maybe (Nat, Nat)
finite (Measured gain loss) = Just (gain, loss)
finite Unmeasured = Nothing

||| The heavier of two Finite weights, by cross-addition.
heavier : (Nat, Nat) -> (Nat, Nat) -> (Nat, Nat)
heavier (a, b) (c, d) = if a + d >= c + b then (a, b) else (c, d)

simple : (n : Nat) -> List (List (Fin n))
simple n = concatMap (\v => grow n [v]) every
  where
    every : List (Fin n)
    every = toList (Data.Vect.allFins n)
    grow : Nat -> List (Fin n) -> List (List (Fin n))
    grow Z path = [path]
    grow (S k) path = path :: concatMap (\v => if elem v path then [] else grow k (path ++ [v])) every

Best : Nat -> Type
Best n = Vect n (Vect n (Maybe (Nat, Nat)))

bestOf : (g : Graph) -> Best g.size
bestOf g = foldl add (replicate g.size (replicate g.size Nothing)) g.arcs
  where
    add : Best g.size -> Arc g.size -> Best g.size
    add b (MkArc q p (Measured gain loss)) = updateAt q (updateAt p (Just . maybe (gain, loss) (heavier (gain, loss)))) b
    add b (MkArc _ _ Unmeasured) = b

at : Best n -> Fin n -> Fin n -> Maybe (Nat, Nat)
at b q p = index p (index q b)

||| A list of positions read as a cycle: its gains and losses, the arcs
||| the heaviest, if every pair has one.
cycleSum : Best n -> List (Fin n) -> Maybe (Nat, Nat)
cycleSum b [] = Nothing
cycleSum b (c :: cs) = go (c :: cs) (0, 0)
  where
    add : (Nat, Nat) -> (Nat, Nat) -> (Nat, Nat)
    add (a, b) (c, d) = (a + c, b + d)
    go : List (Fin n) -> (Nat, Nat) -> Maybe (Nat, Nat)
    go [] acc = Just acc
    go [x] acc = add acc <$> at b x c
    go (x :: y :: rest) acc = at b x y >>= \w => go (y :: rest) (add acc w)

gains : Maybe (Nat, Nat) -> Bool
gains (Just (a, b)) = a > b
gains Nothing = False

linked : Best n -> List (Fin n) -> Bool
linked b (x :: y :: rest) = isJust (at b x y) && linked b (y :: rest)
linked b _ = True

starts : Fin n -> List (Fin n) -> Bool
starts q (x :: _) = x == q
starts q [] = False

record Truth (n : Nat) where
  constructor MkTruth
  positive : List (List (Fin n))
  reach : Vect n (Vect n Bool)
  stuck : List (Nat, Fin n)

truth : (g : Graph) -> Truth g.size
truth g =
  let b = bestOf g
      ps = simple g.size
      fs = Data.Vect.allFins g.size
      j = joinsOf g in
  MkTruth (filter (gains . cycleSum b) ps)
          (map (\q => map (\p => q == p || any (\c => starts q c && last' c == Just p && chained j c) ps) fs) fs)
          (map (\(i, r) => (i, r.from)) (filter (isStuck . label . snd) (zip [0 .. length g.arcs] g.arcs)))
  where
    joinsOf : (g : Graph) -> Vect g.size (Vect g.size Bool)
    joinsOf g = foldl (\m, r => updateAt r.from (replaceAt r.to True) m) (replicate g.size (replicate g.size False)) g.arcs
    chained : Vect g.size (Vect g.size Bool) -> List (Fin g.size) -> Bool
    chained j (x :: y :: rest) = index y (index x j) && chained j (y :: rest)
    chained j _ = True

reaches : Truth n -> Fin n -> Fin n -> Bool
reaches t q p = index p (index q t.reach)

same : Truth n -> Fin n -> Fin n -> Bool
same t q p = index p (index q t.reach) && index q (index p t.reach)

arcAt : (g : Graph) -> Fin (length g.arcs) -> Arc g.size
arcAt = arc

||| The positions a cycle's arcs leave, in order.
positionsOf : (g : Graph) -> List (Fin (length g.arcs)) -> List (Fin g.size)
positionsOf g = map (\a => (arcAt g a).from)

closes : (g : Graph) -> List (Fin (length g.arcs)) -> Bool
closes g as = case positionsOf g as of
  [] => False
  c :: cs => all link (zip3 (c :: cs) (cs ++ [c]) as)
               && (any (isStuck . label . arcAt g) as || sum (map fst ws) > sum (map snd ws))
  where
    ws : List (Nat, Nat)
    ws = mapMaybe (finite . label . arcAt g) as
    link : (Fin g.size, Fin g.size, Fin (length g.arcs)) -> Bool
    link (x, y, a) = (arcAt g a).from == x && (arcAt g a).to == y

satisfies : (g : Graph) -> Vect g.size Nat -> Bool
satisfies g pot = all ok g.arcs && all capOk (toList (Data.Vect.allFins g.size))
  where
    ok : Arc g.size -> Bool
    ok r = case r.label of
      Measured gain loss => index r.from pot + gain <= index r.to pot + loss
      Unmeasured => False
    capOk : Fin g.size -> Bool
    capOk p = maybe True (\c => c <= g.constant + index p pot) (index p g.caps)

||| The least potential, by brute force, when no cycle grows: at each
||| position, the most any simple walk into it weighs, starting at any
||| position at the least its cap asks, and never below 0.
least : (g : Graph) -> Vect g.size Nat
least g = map most (Data.Vect.allFins g.size)
  where
    -- the most the cap of p asks of it: the cap less K
    floorOf : Fin g.size -> Nat
    floorOf p = maybe 0 (\c => minus c g.constant) (index p g.caps)
    -- a walk's value, from its first position's floor, each arc read as the least that satisfies it
    along : List (Fin g.size) -> Maybe Nat
    along [] = Nothing
    along (x :: rest) = go (floorOf x) x rest
      where
        go : Nat -> Fin g.size -> List (Fin g.size) -> Maybe Nat
        go v here [] = Just v
        go v here (y :: ys) = (\(gain, loss) => minus (v + gain) loss) <$> at (bestOf g) here y >>= \v' => go (max v' (floorOf y)) y ys
    most : Fin g.size -> Nat
    most p = foldl max (floorOf p) (mapMaybe (\c => if last' c == Just p then along c else Nothing) (simple g.size))

inside : Truth n -> List (Fin n) -> List (Fin n) -> Bool
inside t [] _ = False
inside t (x :: _) c' = all (same t x) c'

||| Whether any reported cycle reaches a position.
reachedBy : Truth n -> List (List (Fin n)) -> Fin n -> Bool
reachedBy t cs p = any (any (\q => reaches t q p)) cs

cycleOf : Cause g -> Maybe (List (Fin (length g.arcs)))
cycleOf (Cycle as _) = Just as
cycleOf (Unbounded _ _) = Nothing

opaqueOf : Cause g -> Maybe Nat
opaqueOf (Unbounded a _) = Just (finToNat a)
opaqueOf (Cycle _ _) = Nothing

judge : Graph -> Maybe String
judge g =
  let t = truth g
      grows = not (null t.stuck) || not (null t.positive) in
  case check g of
    Bounded pot _ =>
      if grows then Just "bounded, but it grows"
      else if not (satisfies g pot) then Just "bounded by a potential an arc violates"
      else if not (satisfies g (dagPotential g)) then Just "the potential over the components violates an arc"
      else if toList pot /= toList (dagPotential g) then Just "bounded by a potential other than the components'"
      else if toList pot /= toList (least g) then Just "bounded by a potential that is not the least"
      else Nothing
    Grows causes =>
      let cycles = mapMaybe cycleOf (forget causes)
          cs = map (positionsOf g) cycles
          opaques = mapMaybe opaqueOf (forget causes) in
      if not grows then Just "grows, but brute force finds no growth"
      else if not (all (closes g) cycles) then Just "a reported cycle does not close or grow"
      else if any (any (isStuck . label . arcAt g)) cycles then Just "a reported cycle holds a Stuck arc"
      else if not (all (\c => length (filter (inside t c) cs) == 1) t.positive) then Just "a component holding a positive cycle has not exactly one reported"
      else if not (all (\a => elem a (map fst t.stuck)) opaques) then Just "a reported opaque arc is not Stuck"
      else if not (all (\(a, q) => if elem a opaques then not (reachedBy t cs q) else reachedBy t cs q) t.stuck)
        then Just "an opaque arc reported though a cycle reaches it, or left out though none does"
      else Nothing

power : Nat -> List a -> List (List a)
power Z _ = [[]]
power (S k) vs = concatMap (\v => map (v ::) (power k vs)) vs

graphOf : (n : Nat) -> (k : Nat) -> Vect n (Maybe Nat) -> List ((Fin n, Fin n), Maybe Label) -> Graph
graphOf n k caps ws = MkGraph n (mapMaybe slot ws) k caps
  where
    slot : ((Fin n, Fin n), Maybe Label) -> Maybe (Arc n)
    slot ((q, p), w) = case index p caps of
      Just _ => Nothing
      Nothing => MkArc q p <$> w

||| Every graph on n positions under each cap vector, one weight from vs
||| in each slot into an uncapped position.
family : (n : Nat) -> List (Vect n (Maybe Nat)) -> List (Maybe Label) -> List Graph
family n capss vs = concatMap one capss
  where
    one : Vect n (Maybe Nat) -> List Graph
    one caps =
      let fs = toList (Data.Vect.allFins n)
          slots = filter (\(_, p) => isNothing (index p caps)) (concatMap (\q => map (q,) fs) fs) in
      map (\ws => graphOf n 2 caps (zip slots ws)) (power (length slots) vs)

||| Two positions, two arcs each way between them and one loop on each.
parallel : List (Maybe Label) -> List Graph
parallel vs =
  let slots = the (List (Fin 2, Fin 2)) [(0, 0), (0, 1), (0, 1), (1, 0), (1, 0), (1, 1)] in
  map (\ws => graphOf 2 2 [Nothing, Nothing] (zip slots ws)) (power 6 vs)

||| The hand cases, each a name and its graph; expected-stdout gives each
||| one's verdict.
hand : List (String, Graph)
hand =
  [ ("no positions", MkGraph 0 [] 0 [])
  , ("grow once", MkGraph 2 [MkArc 0 1 (Measured 1 0)] 1 [Nothing, Nothing])
  , ("grow, then shrink", MkGraph 2 [MkArc 0 1 (Measured 1 0), MkArc 1 0 (Measured 0 1)] 1 [Nothing, Nothing])
  , ("grow twice, shrink once", MkGraph 2 [MkArc 0 1 (Measured 2 0), MkArc 1 0 (Measured 0 1)] 1 [Nothing, Nothing])
  , ("a mutual +1", MkGraph 2 [MkArc 0 1 (Measured 1 0), MkArc 1 0 (Measured 0 0)] 1 [Nothing, Nothing])
  , ("a cap", MkGraph 1 [] 1 [Just 2])
  , ("the same, uncapped", MkGraph 1 [MkArc 0 0 (Measured 1 0)] 1 [Nothing])
  , ("a stuck arc on no cycle", MkGraph 2 [MkArc 0 1 Unmeasured] 1 [Nothing, Nothing])
  , ("two loops, one growing", MkGraph 1 [MkArc 0 0 (Measured 0 0), MkArc 0 0 (Measured 1 0)] 1 [Nothing])
  , ("a stuck arc a growing cycle reaches", MkGraph 2 [MkArc 0 0 (Measured 1 0), MkArc 0 1 Unmeasured] 1 [Nothing, Nothing])
  , ("two growing components", MkGraph 2 [MkArc 0 0 (Measured 1 0), MkArc 1 1 (Measured 1 0)] 1 [Nothing, Nothing])
  ]

capsOf : (n : Nat) -> List (Maybe Nat) -> List (Vect n (Maybe Nat))
capsOf Z _ = [[]]
capsOf (S k) cs = concatMap (\c => map (c ::) (capsOf k cs)) cs

||| An arc as `from->to gain/loss` or `from->to stuck`.
shown : Arc n -> String
shown (MkArc q p l) = show (finToNat q) ++ "->" ++ show (finToNat p) ++ " " ++ weighs l
  where
    weighs : Label -> String
    weighs (Measured gain loss) = show gain ++ "/" ++ show loss
    weighs Unmeasured = "stuck"

||| A graph as its arcs, and its caps as `p<=c`.
describe : Graph -> String
describe g = unwords (map shown g.arcs ++ mapMaybe cap (toList (zip (Data.Vect.allFins g.size) g.caps)))
  where
    cap : (Fin g.size, Maybe Nat) -> Maybe String
    cap (p, c) = (\c' => show (finToNat p) ++ "<=" ++ show c') <$> c

run : String -> List Graph -> IO ()
run name gs = do
  let bad = mapMaybe (\g => map (\why => why ++ ": " ++ describe g) (judge g)) gs
  let grow = length (filter (\g => let t = truth g in not (null t.stuck) || not (null t.positive)) gs)
  putStrLn (name ++ ": " ++ show (length gs) ++ " graphs, " ++ show grow ++ " grow, " ++ show (length bad) ++ " disagree")
  traverse_ putStrLn (take 5 bad)

main : IO ()
main = do
  let w10 = [Nothing, Just (Measured 0 2), Just (Measured 0 1), Just (Measured 0 0), Just (Measured 1 0), Just (Measured 2 0), Just (Measured 1 1), Just (Measured 1 2), Just (Measured 3 1), Just Unmeasured]
  let w4 = [Nothing, Just (Measured 0 1), Just (Measured 0 0), Just (Measured 1 0)]
  -- A reach a bounded component passes on, from a growing cycle to a Stuck
  -- arc past it, takes three positions and a Stuck weight.
  let w4s = [Nothing, Just (Measured 0 0), Just (Measured 1 0), Just Unmeasured]
  let cap3 = [Nothing, Just 1, Just 4]
  run "one position" (family 1 (capsOf 1 cap3) w10)
  run "two positions" (family 2 (capsOf 2 cap3) w10)
  run "three positions" (family 3 [[Nothing, Nothing, Nothing], [Just 4, Nothing, Nothing]] w4)
  run "three positions, stuck" (family 3 [[Nothing, Nothing, Nothing]] w4s)
  run "parallel arcs" (parallel w4)
  for_ hand $ \(name, g) => do
    let kind = case check g of
                 Grows cs => "grows, " ++ show (length (forget cs)) ++ (if length (forget cs) == 1 then " cause" else " causes")
                 Bounded _ _ => "bounded"
    putStrLn (name ++ ": " ++ kind ++ maybe "" (", " ++) (judge g))
